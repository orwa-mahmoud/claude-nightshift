# The resolved-policy line for one support bundle. Known sensitive fields ship as length.
#
# export-support.sh never ships a policy file, only this view: for every effective setting,
# its value, source, and expiry — except the four owner free-form rule patterns
# (forbiddenCommands, protectedDirs, neverCommitPatterns, expectedEmail), which always ship as
# their length, whatever it is, and any other setting whose value runs past 80 characters, which
# ships the same way. Sources and expiries always ship in full.

.settings
| to_entries[]
| (.key) as $k
| (.value.value | if type == "string" then . else tojson end) as $text
| ($text | length) as $len
| ((["forbiddenCommands", "protectedDirs", "neverCommitPatterns", "expectedEmail"] | index($k)) != null) as $freeform
| (if $freeform or ($len > 80) then "<redacted \($len) chars>" else $text end) as $shown
| "\($k)=\($shown) (\(.value.source), \(.value.expiry))"
