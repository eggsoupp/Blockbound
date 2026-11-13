# Island owner lookup investigation

The reported message is emitted only for `IslandSaveProblem = "owner unknown"`
in IslandService. It is not the inventory save-lock or game-pass denial message.
Tester: alexIz_awsome, user ID 1749102129. Their existing island reportedly stopped
opening after updates. No live island server logs were supplied.

Confirmed defect: resolveOwner exited immediately when the reverse and forward
lookups successfully returned no record, bypassing OWNER_LOOKUP_SECONDS. Mocked
cross-server visibility delay reproduced failure on the original Studio source.

Changed IslandService to retry missing records until the existing 45-second
deadline. Changed IslandDirectory ownership reads to DataStoreGetOptions with
UseCache=false so repeated queries do not reuse cached results. Ownership still
requires a server-side reservation match; client teleport data is never trusted.
No save keys, reservation codes, island contents or account data were changed.

Verification in Studio edit context, without real DataStore calls:
- Original source fails `new reservation becomes visible` regression.
- Patched source passes six resolution cases: delayed visibility, transient error,
  forward lookup for slot 2, unknown reservation rejection after 45 seconds,
  existing reservation, and Studio/public fallback.
- Five mocked directory reads require fresh-read options; legacy numeric and
  slot-2 mappings, reverse-link repair, and mismatched-server rejection pass.
- Both production sources compile; git diff --check passes.

Patched local source and the connected World Studio place. Backups are stored as
StringValues in ServerStorage.BeforeIslandOwnerRetryFix. Not published.

Read-only inspection succeeded after permission was enabled (2026-11-12):
- Account 1749102129 has a slot-1 reservation with a nonempty access code.
- Its reverse server link correctly identifies account 1749102129.
- PlayerIslands_v1/island_1749102129 exists, saved 2026-11-02 19:05:37 UTC.
- Pure decode succeeds: 5,675 edits across 9 chunks, 2 stations, zero problems.
- No slot-2 reservation or save exists. No access codes were output and no
  DataStore writes were made. The earlier report of possibly no saved island
  is resolved: a decodable saved island does exist now.
- Place metadata: Island updateTime 2026-11-12 12:51:53 UTC; World updateTime
  2026-11-12 15:50:28 UTC. These timestamps do not reveal published source code.

Outstanding: the tester-specific historical failure remains unconfirmed without
the failing island server's logs/version. The mapping is currently consistent;
do not reset, replace or re-reserve their island. The reproduced retry defect is
fixed locally and in the open World Studio place, but not deployed to the Island
place. Both places must receive the applicable code changes before live validation
in fresh servers. Saved content after November 2 cannot be inferred from this read.
