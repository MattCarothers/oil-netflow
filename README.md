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

## Redis configuration

This script doesn't set any expiration on the keys.  Once you put an IP into OIL, it stays there forever.  That may or may not be a good idea for your environment.  You'll want to ensure you have enough RAM to hold the number of keys you expect to see.  You may also want to configure Redis to save its database to disk at a longer interval than the default.  For example, this configures a one hour save interval:
```
save 3600 1
```
If your Redis server listens on an external port, you'll want to set an authentication key as well.
```
requirepass your_password_here
```
