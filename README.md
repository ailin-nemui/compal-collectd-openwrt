Record Compal Cable Modem stats in OpenWRT

Tested with Compal CH7466CE / Vodafone KD

Install luci-app-statistics and collectd-mod-exec.

Configure `exec-cmstat.sh` as custom command for the exec plug-in and `custom.types.db` as collectd TypesDB

