# UNDERTOW - playing online with friends

This guide gets 2 to 4 friends into one UNDERTOW match, each on their own PC.
One friend hosts. The others join the host. There is no server and no game
account. Everything here is free.

Short version: everyone installs Tailscale, the host invites the friends,
the host picks Host Match, and friends type the host's TAILSCALE address.


## What you need

- **The same UNDERTOW version on every PC.** Main menu > Play Online shows
  a VERSION line at the bottom. It must match on every PC. If it does not,
  joining stops with DIFFERENT VERSIONS. Everyone should use the same zip.
- **2 to 4 PCs** (Windows), each with UNDERTOW and its own keyboard or
  gamepad.
- **The same song files.** The game never sends songs over the network.
  The bundled songs are always the same. For songs you added yourself,
  every friend needs the same song folder. If a friend lacks the song, the
  lobby shows MISSING next to their name. If their copy is different, it
  shows CHANGED. Copy the song folder to them (into their Songs folder,
  then restart UNDERTOW) or pick another song.
- **A way for the PCs to reach each other.** Pick one of the 4 options
  below. Option 1 (Tailscale) works for almost everyone.

Free-plan numbers below were checked on 2026-10-20 (as of 2026-10-20).
Check the vendor's pricing page if you read this much later.


## Option 1: Tailscale (recommended)

Tailscale makes a small private network between your PCs over the
internet. It gets through home routers, also on mobile or "CGNAT"
internet, without touching router settings. The traffic is encrypted.

The free Personal plan allows up to 6 users (as of 2026-10-20), so 4
friends fit easily.

1. **Everyone** downloads Tailscale from https://tailscale.com/download
   and signs in with their own account (Google, Microsoft, GitHub and so
   on). Each person makes their own account. UNDERTOW never asks for it.
2. **The host** invites the friends into their tailnet: in the Tailscale
   admin console (https://login.tailscale.com/admin), open Users and use
   Invite users. Each friend accepts the invite.
   - Alternative: the host can **Share** just their PC (Machines > the
     host PC > Share). Friends accept the share in their own tailnet.
     With Share, friends join using the machine name (see MagicDNS
     below) or the 100.x.y.z address.
3. Check that Tailscale shows **Connected** on every PC.
4. **The host** starts UNDERTOW: Main menu > Play Online > Host Match.
   The right side of the screen lists THIS PC'S ADDRESSES. The one marked
   **TAILSCALE** starts with **100.** (for example 100.101.102.103).
   Send that address to your friends (Discord, WhatsApp...).
5. **Friends** start UNDERTOW: Main menu > Play Online. Type (or Paste)
   the host's address into Address, keep Port at **47474**, and pick
   **Join Match**. You see CONNECTING, CHECKING VERSION, SYNCING CLOCKS
   and then the LOBBY.

**MagicDNS names also work.** If MagicDNS is on in the tailnet (it is on
by default), friends can type the host PC's Tailscale name instead of the
number, for example `gaming-pc` or `gaming-pc.tail1234.ts.net`.

If the host started UNDERTOW before Tailscale connected, wait a few
seconds: the address list refreshes by itself every 5 seconds.


## Option 2: ZeroTier (also free)

ZeroTier works like Tailscale. The free plan allows 10 devices on 1
network (as of 2026-10-20), so 4 PCs fit. The traffic is encrypted.

1. The host makes a free account at https://www.zerotier.com and creates
   a network. Note the 16-character Network ID.
2. Everyone installs ZeroTier from https://www.zerotier.com/download and
   joins that Network ID.
3. The host opens the network page and ticks **Auth** for each friend's
   PC (members are not allowed in until authorized).
4. The host looks up their own ZeroTier address on the network page
   (Managed IP, often 10.x.x.x or 172.x.x.x).
5. The host picks Host Match. Friends type the host's ZeroTier address,
   keep port 47474, and pick Join Match.

The Play Online screen marks ZeroTier addresses as LAN, not TAILSCALE.
That is fine: use the address from the ZeroTier network page.


## Option 3: same Wi-Fi or LAN

If every PC is in the same house on the same router, no extra app is
needed.

1. The host picks Host Match and reads the address marked **LAN** (often
   192.168.x.x or 10.x.x.x).
2. Friends type that address, keep port 47474, and pick Join Match.

On the same LAN you can also try the **1 BEAT LAN** torpedo flight (see
Torpedo flight below).


## Option 4: router port forward (last resort)

Use this only if Tailscale and ZeroTier are not possible.

1. On the host's router, forward **UDP port 47474** (or the port you
   chose) to the host PC's LAN address (the LAN address from Play
   Online). Every router menu is different. Look for "Port forwarding",
   "Virtual server" or "NAT". Pick UDP, not TCP.
2. Find the host's public IP (search "what is my IP" in a browser on the
   host PC) and give it to friends.
3. The host picks Host Match. Friends type the public IP, keep port
   47474, and pick Join Match.

Limits of this path:

- **It does not work behind CGNAT.** If your router's WAN or internet
  address starts with 100.64 to 100.127, or with 10., your provider shares
  one public address between many homes and a port forward cannot reach
  you. Use Tailscale.
- **The traffic is not encrypted** on this path (only game inputs and
  events cross, but still). Tailscale and ZeroTier encrypt.
- **Remove the port forward after playing.** Do not leave the game port
  open to the internet.


## Windows Firewall

The first time you pick Host Match, Windows asks whether UNDERTOW may use
the network.

- Click **Allow** with **Private networks** ticked. Public networks are
  not needed. Only allow UNDERTOW, nothing else.
- If you clicked **Cancel** by mistake, friends get NO ANSWER. To fix it:
  Windows Security > Firewall & network protection > Allow an app through
  firewall > Change settings > find **UNDERTOW** and tick **Private**. If
  UNDERTOW is not in the list, use "Allow another app..." and pick
  UNDERTOW.exe.
- If you moved UNDERTOW.exe to another folder, Windows may ask again.

Joining usually needs no firewall change. Only the host is asked.


## Changing the port

The default port is **47474** (UDP). Change it only if something else uses
it, or if your port forward uses another number.

- Change it in the **Port** field on Play Online, or in Settings > ONLINE
  > Online port. Any number from 1024 to 65535 works.
- **Everyone must use the same number.** The host and every friend.
- If the host sees "Could not open port ...", another program (or a
  second UNDERTOW) is using it. Close that or pick another port.


## Troubleshooting

| What you see | What it means and how to fix it |
|---|---|
| **NO ANSWER** | The host did not answer within 8 seconds. Check that the host is on Host Match (in the lobby), that the host allowed UNDERTOW through Windows Firewall (see above), that you are both Connected in Tailscale, and that you both use the same port. If you use the LAN address, check you are really on the same network. |
| **ADDRESS NOT FOUND** | The address or name was misspelled, or MagicDNS is off. Use the host's 100.x.y.z Tailscale address instead. |
| **DIFFERENT VERSIONS** | The host and you run different builds. Everyone needs the same zip. The VERSION line on Play Online shows which one you have. |
| **LOBBY FULL** | The lobby already has 4 subs. Someone must leave first. |
| **MATCH IN PROGRESS** | The host is in a match. Try again when they are back in the lobby. |
| **CONNECTION LOST** (while joining) | The link dropped during the join. Pick Try Again. If it keeps happening, check that Tailscale is Connected on both PCs. |
| **CONNECTION LOST** (during a match) | No signal from the host for 4 seconds. Either your internet or the host's dropped. The match ends on your PC. Nothing is saved. |
| **HOST LEFT** | The host quit or closed the match. Without the host the match cannot continue. Go back to Play Online and join again when the host is back. |
| **NO HOST SIGNAL** (red, during a match) | Nothing came from the host for 1 second. It goes away when packets come back. If it shows often, the link is weak: try a wired connection, close downloads or streams, or check whether Tailscale shows a "relay" (DERP) connection instead of "direct". |
| **PING in red** in the lobby | The delay to that player is high. The match still works, but torpedo warnings can get shorter than 1 beat. Keep the torpedo flight at 2 BEATS. |
| **MISSING** next to a name | That player does not have the song. Copy the song folder to them and restart UNDERTOW, or pick another song. |
| **CHANGED** / "Your copy of this song differs from the host's" | The player has the song, but a different version of the chart or audio. Copy the host's song folder exactly, or pick another song. |
| "Could not open port ..." (host) | Another program or another UNDERTOW uses that port. Close it or change the port (everyone changes it). |


## What crosses the network

- Only your inputs (which lane you hit, and when) and game events
  (torpedoes, hull damage, results). Never files, never songs, never
  anything from your PC.
- There are no game accounts and no game servers. The host's PC runs the
  match. Tailscale or ZeroTier accounts are with those companies, not
  with UNDERTOW, and each player makes their own.
- Hit timing is judged on your own PC, so your notes feel the same
  online as offline.


## Torpedo flight

In the lobby the host picks the **Torpedo flight**:

- **2 BEATS** (default): safe for internet play. You still get a warning
  before a torpedo lands.
- **1 BEAT LAN**: faster, for PCs in the same room or on the same LAN
  only. Over the internet the warning can arrive too late to react.


## Reporting problems

When something goes wrong, please note:

- what the screen said (the title, like NO ANSWER), and when it happened,
- the **PING** shown in the lobby for each player,
- how you connected (Tailscale, ZeroTier, LAN or port forward),
- during a match, press **F3** to show the timing overlay. In an online
  match it adds network rows (ping, skew, landed late). A screenshot of
  it helps a lot (Win + Shift + S).

If the game crashed, send the file godot.log from
%APPDATA%\Godot\app_userdata\UNDERTOW\logs (paste that path into the
Explorer address bar).
