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

There are a couple of issues with this

- If the DHCP/Owner configured DNS server (`192.168.1.253`) responds with `REFUSED`, `SERVFAIL` or `NXDOMAIN` the query will be retried via Cloudflare
- Behaviour has been observed where it then won't switch back to local DNS for later queries
- Where queries are sent to CF, local DNS names may be leaked
- HomeAssistant users have, in effect, been signed up to [this](https://developers.cloudflare.com/1.1.1.1/privacy/public-dns-resolver) without their knowledge
- Health check probes will be sent to cloudflare every 5 minutes

The latter is particularly problematic, because if healthchecks fail, they are retried at smaller and smaller intervals. So HomeAssistant users who have blocked `1.1.1.1:853` outbound will find their [HomeAssistant installation flinging packets at it](https://github.com/home-assistant/plugin-dns/pull/56#issuecomment-928967969).

----

### Upstream

This has been reported upstream, and [Pull Requests have been made](https://github.com/home-assistant/plugin-dns/pull/56), but have been [roundly rejected](https://github.com/home-assistant/plugin-dns/pull/56#issuecomment-929700917).

The pro-offered solution of running a container installation isn't *really* a solution, given it entirely ignores the reasons that people want HA-OS.

Issues have been raised and [closed](https://github.com/home-assistant/supervisor/issues/1877) on some extremely spurious grounds.

Unfortunately, despite this being a clear issue with HomeAssistant, it is not going to get addressed in the short-term: the devs are neither willing to do the work, or accept PRs from people who have.

----

### This Addon

This add-on is a fix that shouldn't need to exist, and in it's current state is *unbelievably* dirty, but should be less prone to silently reverting after upgrade/restart than manually editing files.

This addon runs a privileged container (yeuch). But, it needs to be privileged so that it can communicate with the docker daemon.

This allows it to, once a minute:

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
### TODO

There are a number of improvements that can be made


- At the moment, there's a stream of `sed` commands used to patch out the cloudflare bits, it's plausible that a future update might lead to this creating broken config. A better route would be to have a template, pull the list of local DNS servers out of the DNS container, populate the template and copy that over

- Tidy up config etc: the skeleton of the addon is derived from one of the SSH addons - I wanted to build quick to prove the concept. Currently the config page has a "Show WEB UI" button as a result


