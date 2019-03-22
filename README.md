# redirects

I maintain a bunch of convenience redirect URLs. The more scalable thing to do
would be to bring up HAProxy and define them all as reverse proxies, but why do
that when I can use S3 instead?

# Creating a new redirect

1. Run `scripts/create_redirect.sh [URL] [URL_TO_FORWARD_TO]`.
   This will create the redirect file in this repo's toplevel.

2. Deploy: `scripts/deploy.sh`
