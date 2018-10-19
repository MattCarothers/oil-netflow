# oil-netflow
Observed Indicator List (OIL) for Netflow

This script dumps flow information from nfcapd netflow binaries and stores the most recent flow for every IP address in a Redis key/value store.

Given a flow like this ...

```
Date first seen          Proto  Src IP Addr:Port     Dst IP Addr:Port
2018-10-19 10:14:50.000   UDP   10.0.0.1:36020   <-> 8.8.8.8:53
```
... we set a Redis key like this:
```
172.17.0.2:6379> get oil:8.8.8.8
"/netflow/2018/10/19/router1/nfcapd.201810191010:10.0.0.1:8.8.8.8:36020:53:UDP"
```

Now we have a very quick yes or no answer as to whether we've seen an IP in our environment.  If the answer is yes, we also know the most recent time we saw it.
