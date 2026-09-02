# The JSON half of evidence.sh: lift values out of a record, put chosen values back in.
#
# evidence.sh owns every ledger decision — defaults, validation order, dispositions,
# rendering. This program never decides anything; it reads and it writes. Three operations,
# selected by $op, all of them sharing the same argument set so one shell wrapper can bind it:
#
#   facts  slurped input. One tab-separated fact per line per record: t type, q required-key
#          presence bits, h default-key presence bits, s schemaVersion==1, v field value by
#          slot. Every payload is a JSON text, so it carries no tab and no newline and the
#          stream stays line-safe.
#   rows   slurped input. The render and export columns exactly as Python's str() prints
#          them, $FS between fields, presence bits last, $RS between records — so a column
#          value may hold anything.
#   edit   one record in, the $ops assignments applied, one record out.

def pyrepr:
  if type == "array" then "[" + ([.[] | pyrepr] | join(", ")) + "]"
  elif type == "object"
  then "{" + ([to_entries[] | (.key | pyrepr) + ": " + (.value | pyrepr)] | join(", ")) + "}"
  elif type == "string" then "'" + (gsub("\\\\"; "\\\\") | gsub("'"; "\\'")) + "'"
  elif . == null then "None"
  elif . == true then "True"
  elif . == false then "False"
  else tostring
  end;

def pystr:
  if type == "string" then .
  elif type == "array" or type == "object" then pyrepr
  elif . == null then "None"
  elif . == true then "True"
  elif . == false then "False"
  else tostring
  end;

def names($s): $s | split("\n") | map(select(length > 0));

def field($k): if type == "object" then .[$k] else null end;

def presence($keys): . as $r
  | [$keys[] | . as $k | if ($r | type) == "object" and ($r | has($k)) then "1" else "0" end]
  | join("");

def facts($i; $req; $hkeys; $fields; $T): . as $r
  | ("t" + $T + ($i | tostring) + $T + ($r | type)),
    ("q" + $T + ($i | tostring) + $T + ($r | presence($req))),
    ("h" + $T + ($i | tostring) + $T + ($r | presence($hkeys))),
    ("s" + $T + ($i | tostring) + $T
      + (if ($r | field("schemaVersion")) == 1 then "1" else "0" end)),
    ($fields | to_entries[] | .key as $slot | .value as $k
      | "v" + $T + ($i | tostring) + $T + ($slot | tostring) + $T
        + ($r | field($k) | tojson));

def rows($cols; $FS; $RS): . as $r
  | ([$cols[] | . as $c | $r | field($c) | pystr] | map(. + $FS) | join(""))
    + ($r | presence($cols)) + $RS;

def edit($assign; $FS; $RS):
  reduce ($assign | split($RS) | .[] | select(length > 0)) as $a (.;
    ($a | split($FS)) as $f
    | if $f[1] == "s" then .[$f[0]] = $f[2]
      elif $f[1] == "n" then .[$f[0]] = ($f[2] | tonumber)
      else .[$f[0]] = .[$f[2]]
      end);

  names($req) as $REQ
| names($hkeys) as $HKEYS
| names($fields) as $FIELDS
| names($cols) as $COLS
| if $op == "facts" then (to_entries[] | .key as $i | .value | facts($i; $REQ; $HKEYS; $FIELDS; $T))
  elif $op == "rows" then (.[] | rows($COLS; $FS; $RS))
  else edit($assign; $FS; $RS)
  end
