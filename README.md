# redirects

I maintain a bunch of convenience redirect URLs. The more scalable thing to do
would be to bring up HAProxy and define them all as reverse proxies, but why do
that when I can use S3 instead?

# How to use

**NOTE**: You need to have Docker installed first.

1. Copy `.env.example` to `.env`. Fill in the values that say "change me"
2. Run `scripts/test.sh` to verify that everything being created looks good.
3. Run `scripts/deploy.sh` to deploy those changes.
