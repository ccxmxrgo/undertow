class_name NetProtocol
extends RefCounted
## The online wire vocabulary and its hard limits (D-01, D-02, D-21, D-23).
##
## Trust model: peers are friends, but their bytes are untrusted. Every packet from any peer
## (the host included, Pitfall 6) goes through NetCodec.decode, which applies the schemas and
## caps declared here. Seats are never read from a payload; they come from the sender's peer id.
##
## Transport: channel 0 is reliable-ordered (lobby, inputs, events), channel 1 is unreliable
## (clock pings, heartbeats). All traffic is plain Variant Dictionaries {type: <const>, ...}
## sent as bytes; there are no @rpc calls (D-02).

const PROTO := 1
const DEFAULT_PORT := 47474
const MAX_CLIENTS := 3
const MAX_SEATS := 4
const CH_RELIABLE := 0
const CH_UNRELIABLE := 1

# --- Caps (D-23) --------------------------------------------------------------------------------
## Packets larger than this are rejected before any decoding.
const MAX_PACKET := 16384
## Items per INPUTS batch and events per EVENTS batch.
const MAX_BATCH := 128
## Generic string cap (codes, reasons, event strings, medal ids, version strings).
const MAX_STR := 32
## Display names: 1-12 chars of [A-Z0-9 _-] after upper-casing (D-20).
const MAX_NAME := 12
const MAX_WARHEADS := 16
## Any Array inside an event (warheads, ids, standings).
const MAX_EVENT_ARRAY := 16
## RESULTS rows / roster entries.
const MAX_ROWS := 4
## Song title / artist / fingerprint text cap (LOBBY song, RESULTS).
const MAX_TEXT := 64
## Typical packet budget (Tailscale MTU 1280); a soft target, not enforced by the codec.
const TARGET_PACKET := 1200

# --- Timeouts and timing (D-05, D-07, D-17, D-21) ------------------------------------------------
const AUTH_TIMEOUT_S := 3.0
const CONNECT_TIMEOUT_S := 8.0
const WATCHDOG_S := 4.0
const LINK_WEAK_S := 1.0
const LOAD_TIMEOUT_S := 15.0
const START_DELAY_S := 3.0
const MIN_LEAD_S := 0.5
const D_MIN_S := 0.060
const D_MAX_S := 0.200

# --- Rate limits (Security V5) -------------------------------------------------------------------
const MAX_INPUTS_PER_S := 240
## PING token-bucket refill rate per second.
const MAX_PINGS_PER_S := 20
## PING token-bucket capacity; overflow is dropped silently, never a strike.
const PING_BUCKET := 40
const STRIKES_TO_KICK := 3
## Inputs stamped further than this beyond the host's song time are dropped (HostInputQueue).
const FUTURE_INPUT_S := 2.0

## Accepted wire time range is [TIME_MIN_S, song_len + TIME_SLACK_S].
const TIME_MIN_S := -10.0
const TIME_SLACK_S := 30.0
## Upper bound for any song length (LOAD.max_song_s, and the time range when ctx has no song).
const MAX_SONG_S := 1200.0

# --- Message types -------------------------------------------------------------------------------
# Both directions.
const PING := "ping"  ## {seq:int, c0:int}
const PONG := "pong"  ## {seq:int, c0:int, h:int}
# Client -> host.
const AUTH := "auth"  ## {proto:int, game:String, name:String} (send_auth payload)
const READY := "ready"  ## {ready:bool, synced:bool}
const SONG_STATUS := "song_status"  ## {status: SONG_STATES, synced:bool}
const LOADED := "loaded"  ## {}
const LOAD_FAIL := "load_fail"  ## {}
const START_LATE := "start_late"  ## {lead_ms:int}
const INPUTS := "inputs"  ## {items: Array <= MAX_BATCH of [kind, t, seq, ...args]}
const DONE := "done"  ## {t:float}
const HEARTBEAT := "heartbeat"  ## {song_t:float, ticks:int}
const BYE := "bye"  ## {}
# Host -> client.
const AUTH_REPLY := "auth_reply"  ## {ok:bool, reason:String, host_version:String}
const LOBBY := "lobby"  ## {roster, song, flight, phase}
const NOTICE := "notice"  ## {code:String, name:String, n:int}
const KICKED := "kicked"  ## {reason}
const LOAD := "load"  ## {fp, sig, diff, seed, flight, roster, d_ms, max_song_s, autoplay}
const START := "start"  ## {host_start_ticks:int}
const ABORT_TO_LOBBY := "abort_to_lobby"  ## {reason, name}
const EVENTS := "events"  ## {seq:int, events: Array <= MAX_BATCH of GameEvent records}
const RESULTS := "results"  ## see NetCodec._v_results
const BACK_TO_LOBBY := "back_to_lobby"  ## {}
const MATCH_ABORT := "match_abort"  ## {reason}
const LOBBY_CLOSED := "lobby_closed"  ## {}

const FROM_CLIENT: Array[String] = [
	PING, PONG, AUTH, READY, SONG_STATUS, LOADED, LOAD_FAIL, START_LATE, INPUTS, DONE,
	HEARTBEAT, BYE,
]
const FROM_HOST: Array[String] = [
	PING, PONG, AUTH_REPLY, LOBBY, NOTICE, KICKED, LOAD, START, ABORT_TO_LOBBY, EVENTS, RESULTS,
	BACK_TO_LOBBY, MATCH_ABORT, LOBBY_CLOSED,
]

# --- INPUTS item kinds (shared by RemoteReferee and HostInputQueue, 04-05) -----------------------
## Item wire shape: [kind:int, t:float, seq:int >= 0, ...args]; args per IN_ARITY.
const IN_JUDGED := 0  ## [note_index:int, judgment:int]
const IN_EXTRA := 1  ## [judgment:int]
const IN_STRAY := 2  ## []
const IN_GHOST := 3  ## []
const IN_STATUS := 4  ## [hull:float, depth:float, accuracy:float, max_streak:int]
const IN_FIRE := 5  ## []
const IN_CYCLE := 6  ## []
const IN_TARGET_MODE := 7  ## [mode:int (PlayerState.TargetMode), locked:int seat or -1]
const IN_FAILED := 8  ## []
const IN_APPROACH := 9  ## [approach_s:float]
const IN_ARITY := {
	IN_JUDGED: 2, IN_EXTRA: 1, IN_STRAY: 0, IN_GHOST: 0, IN_STATUS: 4, IN_FIRE: 0, IN_CYCLE: 0,
	IN_TARGET_MODE: 2, IN_FAILED: 0, IN_APPROACH: 1,
}
## Items carry 3 header fields before the args.
const ITEM_HEAD := 3

# --- Reason codes (AUTH_REPLY, KICKED, ABORT_TO_LOBBY, MATCH_ABORT) ------------------------------
const R_VERSION := "version"
const R_FULL := "full"
const R_IN_MATCH := "in_match"
const R_KICKED := "kicked"
const R_HOST_LEFT := "host_left"
const R_PROTO := "proto"
const R_BAD_NAME := "bad_name"
const R_LOAD_TIMEOUT := "load_timeout"
const R_START_LATE := "start_late"
const R_LOAD_FAIL := "load_fail"
const R_CLOSED := "closed"
const REASONS: Array[String] = [
	R_VERSION, R_FULL, R_IN_MATCH, R_KICKED, R_HOST_LEFT, R_PROTO, R_BAD_NAME, R_LOAD_TIMEOUT,
	R_START_LATE, R_LOAD_FAIL, R_CLOSED,
]

## SONG_STATUS.status and LOBBY roster "song" values (D-12).
const SONG_STATES: Array[String] = ["ok", "missing", "changed", "checking"]
const DIFFICULTIES: Array[String] = ["easy", "medium", "hard", "expert"]


## The build version both sides compare in the handshake (D-21). 04-03 sets it to 0.7.0.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))
