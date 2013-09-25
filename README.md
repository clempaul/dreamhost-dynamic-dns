dreamhost-dynamic-dns
=====================

A Dynamic DNS updater for use with the Dreamhost API

- - -

This script updates a DNS A record hosted by Dreamhost to your current IP
address via the Dreamhost API.

You need to have generated an API key from the [web panel][panel] with
permissions for the following requests:

- dns-list_records
- dns-remove_record
- dns-add_record

_WARNING: Do not rely on this script to provide always work perfectly!!
Due to the lack of update\_record API request, we are forced to delete and 
then re-add. If there is a problem with the API, we could end up deleting
a record and then fail to re-add it. If you have this in cron, it will 
likely update the next time the script is run, or you could just be left 
without a DNS record at all._

This script is dependant on the following executables:
`bash` (this is a bash script after all), `wget`, `uuidgen`, `grep`, `awk`

Usage
-----

A Config file `~/.config/dynamicdns` should set two environment variables: 
`KEY` and `RECORD`. These can also be passed on the command line:
e.g. `KEY=my_key RECORD=my.dns.record ./dynamicdns.bash`

Once you've set up your config file, you can easily add this to your crontab
with an entry like

    @hourly ~/bin/dreamhost-dynamic-dns/dynamicdns.bash

[panel]: https://panel.dreamhost.com/