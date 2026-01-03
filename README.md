# Dreamhost Dynamic DNS Script

============================

## A Dynamic DNS updater for use with the Dreamhost API

---

This script updates a DNS A record hosted by Dreamhost to your current IP
address via the Dreamhost API.

You need to have generated an API key from the [web panel][panel] with
permissions for the following requests:

```
- dns-list_records
- dns-remove_record
- dns-add_record
```

_WARNING: Do not rely on this script to always work perfectly!!
Due to the lack of update\_record API request, we are forced to delete and
then re-add. If there is a problem with the API, we could end up deleting
a record and then fail to re-add it. If you have this in cron, it will
likely update the next time the script is run, or you could just be left
without a DNS record at all._

This script is dependant on the following executables:
`bash` (this is a bash script after all), `wget` or `curl`,
`uuidgen`, `grep`, `awk`, `sed`, and `dig`.

## Usage

---

The script can be run using either command line options or a configuration file.
A sample configuration file is found below.

## SYNOPSIS

`*dynamicdns.bash* [-Sdv][-k API Key]
 [-r Record] [-i New IP Address] [-L Logging (true/false)]`

## DESCRIPTION

The `dynamicdns.bash` utility reads a configuration file or command-line options
to update DNS records for a Dreamhost account.  Options provided at the command
line override any options specified within the configuration file.

The options are as follows:

>__-S__ Save any options provided via the command line
to the configuration file.  
>__-d__ Save any options provided via the command line to the configuration file
and do not update DNS.  
>__-v__ Enable verbose mode.  
>__-l__ Enable list-only mode, showing only current value returned
by the Dreamhost API.  
>__-k__ *API Key*  
Dreamhost API Key with dns-list\_records,
dns-remove\_record, and dns-add\_record permissions.  
>__-r__ *Record*  
> The DNS Record to be updated.  
>__-i__ *IP Address*  
> Specify the IPv4 Address to update the Record to.  
If no address is specified, the utility will use __dig__ to
obtain the current public IPv4 Address of your computer.  
>__-L__ *(true/false)*  
> Enables system logging via the __logger__ command.
The configuration file sets logging to *true* by default.

## RUNNING WITH CRON

You can easily add this to your crontab with an entry like

```
  @hourly ~/bin/dreamhost-dynamic-dns/dynamicdns.bash
```

## TODO

---

- Allow disabling of error logging

[panel]: https://panel.dreamhost.com/?tree=home.api
