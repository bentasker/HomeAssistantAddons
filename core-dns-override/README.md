HomeAssistant Core DNS Fix
============================

The following routes of installing HomeAssistant:

- HomeAssistant OS
- Supervised

Both contain a significant, and [poorly documented flaw](https://github.com/home-assistant/home-assistant.io/issues/19511) in their DNS setup.

When installing using these methods, a container `hassio_dns` is run, running a `coredns` install.

Unfortunately, this configuration hardcodes a fallback of Cloudflare's DoT service:

    .:53 {
        log {
            class error
        }
        errors
        loop

        hosts /config/hosts {
            fallthrough
        }
        template ANY AAAA local.hass.io hassio {
            rcode NOERROR
        }
        mdns
        forward . dns://192.168.1.253 dns://127.0.0.1:5553 {
            except local.hass.io
            policy sequential
            health_check 1m
        }
        fallback REFUSED,SERVFAIL,NXDOMAIN . dns://127.0.0.1:5553
        cache 600
    }

    .:5553 {
        log {
            class error
        }
        errors

        forward . tls://1.1.1.1 tls://1.0.0.1  {
            tls_servername cloudflare-dns.com
            except local.hass.io
            health_check 5m
        }
        cache 600
    }

There are a number of issues with this

- If the DHCP/Owner configured DNS server responds with `REFUSED`, `SERVFAIL` or `NXDOMAIN` rather than being respected, the query will be retried via Cloudflare
- The "fallback" (`127.0.0.1:5553`) is specified in the main pool, so will sometimes be used instead of the configured DNS
- Behaviour has been observed where it then won't switch back to local DNS for later queries
- Queries sent to cloudflare will be unable to resolve local names
- Where queries are sent to CF, local DNS names may be leaked
- HomeAssistant users have, in effect, been signed up to [this](https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver) without their knowledge
- Health check probes will be sent to cloudflare every 5 minutes

The latter is particularly problematic, because if healthchecks fail, they are retried at smaller and smaller intervals. So HomeAssistant users who have blocked `1.1.1.1:853` outbound will find their [HomeAssistant installation flinging packets at it](https://github.com/home-assistant/plugin-dns/pull/56#issuecomment-928967969), [another example](https://github.com/home-assistant/plugin-dns/issues/20#issuecomment-917354758).

TL:DR

- HomeAssistant sends queries via Cloudflare's DNS without the user's consent
- HomeAssistant will therefore sometimes fail to resolve local names
- If Cloudflare's DNS is blocked/unreachable, HomeAssistant's DNS plugin will send a flood of retries onto the network
- There is no ability to disable this

----

### Upstream Reports

This has been reported upstream, and [Pull Requests have been made](https://github.com/home-assistant/plugin-dns/pull/56), but have been [roundly rejected](https://github.com/home-assistant/plugin-dns/pull/56#issuecomment-929700917).

The pro-offered solution of running a container installation isn't *really* a solution, given it entirely ignores the reasons that people want HA-OS.

Issues have been raised and [closed](https://github.com/home-assistant/supervisor/issues/1877) on some extremely spurious grounds.

Unfortunately, despite this being a clear issue with HomeAssistant, it is not going to get addressed in the short-term: the devs are neither willing to do the work, or accept PRs from people who have.

----

### This Addon

This add-on is a fix that shouldn't need to exist, and in it's current state is *unbelievably* dirty, but should be less prone to silently reverting after upgrade/restart than manually editing files.

This addon runs a privileged container (yeuch). But, it needs to be privileged so that it can communicate with the docker daemon.

This allows it to, once a minute (configurable):

- Copy `/etc/corefile` from the `hassio_dns` container
- Check whether the Cloudflare config is active
- If it is, remove it, copy the new config up and force a restart of `coredns`

The result is that the `coredns` config will then look more like

```
bash-5.1# cat /etc/corefile 
.:53 {
    log {
        class error
    }
    errors
    loop
    
    hosts /config/hosts {
        fallthrough
    }
    template ANY AAAA local.hass.io hassio {
        rcode NOERROR
    }
    mdns
    forward .  dns://192.168.1.253  {
        except local.hass.io
        policy sequential
        
    }
    
    cache 600
}

.:5553 {
    log {
        class error
    }
    errors
    
    forward . tls://1.1.1.1 tls://1.0.0.1 {
        tls_servername cloudflare-dns.com
        except local.hass.io
        
    }
    cache 600
}

```

(Although still present in the config, the `:5553` section will no longer be used by the resolver listening on `53`)

----

### Installation

To install my repo:

- Log into HomeAssistant
- Head to `Supervisor` -> `Add-On Store`
- Click the overflow menu in the top right
- Click `Repositories`
- Paste `https://github.com/bentasker/HomeAssistantAddons/` and click `Add`
- Click the overflow button and click `Reload`

A new section should appear, if it doesn't hit `System` and then `Restart Supervisor`

Click into the addon and click `Install`

Once installed, click in and choose

- Start on boot
- Protection mode (turn it off)
- Click Start

----

### Notes

The config section relating to port `5553` must be left in place.

It's declared as an ingress port for the DNS container, so if it isn't actively listening the check [here](https://github.com/home-assistant/supervisor/blob/main/supervisor/addons/addon.py#L479) will fail, and `supervisor` will restart the container.

----

### Using a template

The default behaviour of this add-on is to patch the existing config to remove references that lead to the fallback being used.

However, for additional control, you can also provide a config file to be used.

This should be added as `dns-override-template` in your `config` directory:

```
.:53 {
    log {
        class error
    }
    errors
    loop

    hosts /config/hosts {
        fallthrough
    }
    template ANY AAAA local.hass.io hassio {
        rcode NOERROR
    }
    mdns
    forward . dns://192.168.1.253 {
        except local.hass.io
        policy sequential
    }
    cache 600
 }

.:5553 {
    log {
        class error
    }
    errors

    forward . dns://192.168.1.253  {
        except local.hass.io
    }
    cache 600
}

```
Note that you must not remove the `:5553` server (see [#Notes](#notes)) - 

In the addon's configuration page, tick `use_dns_template` and restart the addon.

Unfortunately, the template cannot be provided via the configuration page because [HomeAssistant's YAML handling appears to be broken](https://github.com/bentasker/HomeAssistantAddons/commit/a34fb242599c25458094bec3cddccb37f351c2a8).

If you've ticked the box and the config file doesn't exist, the default behaviour of patching existing config will be used, and an error will be logged

```
[12:19:19] ERROR: /config/dns-override-template does not exist - will patch existing file instead
```

Note: if you wish to switch back to using the patching method, after unticking the `use_dns_templatew` option you need to trigger a restart of the DNS container (or just restart the whole system).

----

## Loglines

The following loglines may appear in your logs:

### Informational

```
INFO: Launched
```
Just the addon confirming it's started successfully


```
INFO: Changes detected - overwriting DNS Config
```
This is normally a routine entry - `coredns`'s config had changed away from the desired one, so was overridden.

If you see lots of these in close succession, it suggests the DNS container might be crashing out and restarting, which will need further investigation.


### Errors

```
ERROR: Unable to access docker
```
Logged at startup if it's not possible to communicate with Docker.

Most likely cause is that you forgot to disable protection mode - disable it in the Addon's config page and then restart the addon.


```
ERROR: Did you forget to disable protection mode?
```
Logged as a result of not being able to communicate with docker. This will be logged periodically to improve the chances of you noticing it in your system logs.

Disable protection mode and restart the add-on


```
ERROR: /config/dns-override-template does not exist - will patch existing file instead
```
You've enabled `use_dns_template` but the configuration file could not be found. SSH onto your HomeAssistant box and create the [config file](#using-a-template), or disable `use_dns_template`.

In the meantime, the default patching mode will be used.
