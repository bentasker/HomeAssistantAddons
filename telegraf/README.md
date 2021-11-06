HomeAssistant Telegraf Addon
===============================

[Telegraf](https://github.com/influxdata/telegraf) allows you to capture metrics and write them out to InfluxDB so that you can monitor performance etc.

This Add-on provides a Telegraf instance which you can configured in `/config/` (the addon doesn't ship with any config by default).

See [example_setup.md](example_setup.md) for an example of collecting telemetry from the DNS container.

### Example configuration

    [agent]
    interval = "10s"
    round_interval = true
    metric_batch_size = 300
    metric_buffer_limit = 5000
    collection_jitter = "0s"
    flush_interval = "20s"
    flush_jitter = "0s"
    precision = ""
    debug = false
    quiet = false
    logfile = ""
    # Override the name, or you'll get the containers name
    hostname = "home-assistant"
    omit_hostname = false

    [[inputs.diskio]]
    [[inputs.mem]]
    [[inputs.net]]
    [[inputs.swap]]
    [[inputs.system]]
    [[inputs.cpu]]
    ## Whether to report per-cpu stats or not
    percpu = true
    ## Whether to report total system cpu stats or not
    totalcpu = true
    ## If true, collect raw CPU time metrics.
    collect_cpu_time = false
    ## If true, compute and report the sum of all non-idle CPU states.
    report_active = false

    [[outputs.influxdb]]
    urls = ["<your influxdb url>"]
    database = "<your db>"
    
