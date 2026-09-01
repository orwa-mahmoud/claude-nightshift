# Rebuild the detector document from the record stream detect-capabilities.sh writes.
#
# Each record is  <type> FS <depth> FS <path component> x depth FS <value>  and records are
# separated by RS; both separators arrive as --arg so this program stays free of literal
# control characters. Types: s string, n number, b boolean ("1" is true), z null, j raw
# JSON, A ensure array, a append to array.
reduce (split($RS)[] | select(length > 0)) as $rec ({};
  ($rec | split($FS)) as $f
  | ($f[1] | tonumber) as $d
  | ($f[2:(2 + $d)]) as $p
  | ($f[2 + $d]) as $v
  | ($f[0]) as $t
  | if   $t == "s" then setpath($p; $v)
    elif $t == "n" then setpath($p; ($v | tonumber))
    elif $t == "b" then setpath($p; ($v == "1"))
    elif $t == "z" then setpath($p; null)
    elif $t == "j" then setpath($p; ($v | fromjson))
    elif $t == "A" then setpath($p; (getpath($p) // []))
    elif $t == "a" then setpath($p; ((getpath($p) // []) + [$v]))
    else . end)
