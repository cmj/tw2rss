# tw2rss
### Twitter to RSS generator

 * Requires auth_tokens

```
# copy to cgi-bin
cp tw2rss /usr/lib/cgi-bin/tw2rss

# must be executable
chmod +x /usr/lib/cgi-bin/tw2rss

# Create /etc/apache2/conf-available/tw2rss.conf to set auth_tokens:
SetEnv AUTH_TOKENS token1,token2

# Then enable it:
a2enconf tw2rss
systemctl reload apache2

# access via
http://yourserver/cgi-bin/tw2rss?user=nasa&limit=20&replies=1
```

### Twitter to RSS generator - standalone server

Defaults to host 127.0.0.1, port 8080 and user NASA


`export AUTH_TOKENS=token1,token2,token3`

```
usage: tw2rss-server.py [-h] [--host HOST] [--port PORT] [--user USER]

twitter2rss server

options:
  -h, --help   show this help message and exit
  --host HOST
  --port PORT
  --user USER  Default Twitter username to fetch
```

access via:
`http://127.0.0.1:8080/?user=x&replies=1&limit=5`
