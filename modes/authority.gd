class_name Authority
extends RefCounted
## Who decides what happens in the match. Offline, this machine decides everything. Online, the
## host decides damage, deaths, scores, waves, the flood, the spores and terrain edits, and every
## client only shows what the host sent. Code that makes such a decision asks is_host() first;
## code that presents never does.

## Set false on a client once a networked match starts.
static var host: bool = true


static func is_host() -> bool:
	return host
