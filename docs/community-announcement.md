<!--
First community post for the NS8 Hashtopolis module, written in the style
of https://community.nethserver.org/t/ns8-forgejo-testing/28554 (first post).
Paste into a new topic on community.nethserver.org, category "App", tag "ns8".
Fill in the wiki link once the page is published.
-->

# NS8 Hashtopolis (testing)

Hi all,

I've built an NS8 module for [Hashtopolis](https://github.com/hashtopolis/server) — a distributed wrapper for hashcat, for authorised password recovery and security testing.

It's in my community repository. To try it, add the repo once:

```
api-cli run add-repository --data '{"name":"tebbiworld","url":"https://raw.githubusercontent.com/tebbiworld/ns8-repo/main/ns8/updates/","status":true,"testing":false}'
```

then install **Hashtopolis** from the Software Center. (Or straight from the image: `add-module ghcr.io/tebbiworld/hashtopolis:latest 1`.)

What it does:

* Runs the official Hashtopolis backend and frontend images plus a dedicated MySQL, all in one rootless pod
* Publishes a single Traefik route; the frontend's nginx splits the API, agent and UI paths internally, with the usual Let's Encrypt and HTTP→HTTPS options
* Writes the public base URL into Hashtopolis' `baseHost` setting, so agent-binary downloads and v2 pagination links work correctly behind the reverse proxy
* Keeps jobs, hashlists and results in a named MySQL volume, so they survive restarts and updates

A few things to know:

* For **authorised** password recovery and security testing only — your own hashes, with permission.
* The module packages the server side. You still bring your own agents and hardware (the GPUs doing the actual hashcat work) and register them against the agent URL it shows you.
* It generates an initial `admin` password (read it back with `get-configuration`); log in and change it straight away.
* There's an optional Public URL field for setups where a gateway node terminates TLS while this node serves plain http.
* Upstream images are digest-pinned (upstream doesn't tag releases very often), so updates are deliberate rather than automatic.

It's working well here, but a second pair of eyes is always welcome — if you run it with real agents, I'd be glad to hear how the routing and agent registration behave for you.

Docs: NethServer wiki (tebbiworld repository) · Source: [github.com/tebbiworld/ns8-hashtopolis](https://github.com/tebbiworld/ns8-hashtopolis)

Thanks!

*Category: App · Tags: ns8*
