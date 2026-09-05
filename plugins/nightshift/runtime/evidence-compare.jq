# The JSON half of evidence-compare.sh: lift the comparison inputs out of the ledger.
#
# evidence-compare.sh owns every decision — scope, availability, the class of each finding, the
# mode's verdict, both renderings. This program never decides anything; it reads. One operation:
# the raw ledger text arrives slurped, and one frame per fact leaves, $FS between the fields and
# $RS at the end, so a field may hold any text a record does.
#
#   f  a record: index, then domain, sourceClass, status, disposition, id, digest and locator as
#      compact JSON, then id, digest, locator and sourceClass as display text.
#   s  one entry of that record's sources[]: index, position, "s" for a string or "x", the entry
#      as compact JSON, the entry as display text.
#   e  that record's details.environmentDigest, as compact JSON, when it carries one.
#   o  one entry of that record's details.observed[]: index, position, then the entry's id and
#      digest as compact JSON and as display text.
#   b  the line at that index is not JSON. The shell names it and stops.
#
# A value's compact JSON is self-describing in its first byte and carries no raw newline or tab,
# so the shell compares ids and digests without unescaping them. Display text is
# control-scrubbed, which is what keeps a Markdown row on one line.

def obj: if type == "object" then . else {} end;
def arr: if type == "array" then . else [] end;
def scrub: gsub("[\\x00-\\x1f\\x7f]"; " ");
def txt: (if type == "string" then . else tojson end) | scrub;
def field($k): if type == "object" then .[$k] else null end;
def frame($fields): ($fields | join($FS)) + $RS;

def record($i):
  . as $r
  | ($i | tostring) as $n
  | ($r | field("details") | obj) as $d
  | frame(["f", $n,
           ($r | field("domain") | tojson),
           ($r | field("sourceClass") | tojson),
           ($r | field("status") | tojson),
           ($r | field("disposition") | tojson),
           ($r | field("duplicateOf") | tojson),
           ($r | field("id") | tojson),
           ($r | field("digest") | tojson),
           ($r | field("locator") | tojson),
           ($r | field("id") | txt),
           ($r | field("digest") | txt),
           ($r | field("locator") | txt),
           ($r | field("sourceClass") | txt),
           ($r | field("source") | txt)]),
    ($r | field("sources") | arr | to_entries[]
     | frame(["s", $n, (.key | tostring),
              (if (.value | type) == "string" then "s" else "x" end),
              (.value | tojson), (.value | txt)])),
    (if ($d.environmentDigest | type) == "string"
     then frame(["e", $n, ($d.environmentDigest | tojson)])
     else empty end),
    ($d.seen | arr | to_entries[] | .key as $k | (.value | obj) as $o
     | frame(["o", $n, ($k | tostring),
              ($o.id | tojson), ($o.digest | tojson),
              ($o.id | txt), ($o.digest | txt)]));

  split("\n")
| map(select(. != ""))
| to_entries[]
| .key as $i
| .value as $line
| (try ({v: ($line | fromjson)}) catch null) as $parsed
| if $parsed == null then frame(["b", ($i | tostring)]) else ($parsed.v | record($i)) end
