TODO: make document caching optional

```
key | .append ANTHROPIC_API_KEY
let c = source xs-command-llm.call-anthropic.nu ; do $c.process ("hi" | .append go)
cat xs-command-llm-anthropic.nu | .append llm.define
"hi" | .append llm.call
.cat | where topic == "llm.response" | last | .cas | from json
```

Adhoc request: translate the current clipboard to english

```
[
    (bp)               # our current clipboard: but really you want to "pin" a
                       # snippet of content
    "please translate to english"  # tool selection
]
# we should be able to pipe a list of strings directly into llm.call
| str join "\n\n---\n\n"
| (.append
    -c 03dg9w21nbjwon13m0iu6ek0a # the context which has llm.define and is generally considered adhoc
    llm.call
    )
```


View outstanding calls:


```
.cat | where topic in ["llm.call" "llm.error" "llm.response"] | reduce --fold {} {|frame acc|
     if $frame.topic == "llm.call" {
       return ($acc | insert $frame.id "pending")
     }

     $acc | upsert $frame.meta.frame_id ($frame | reject meta)

   }
```
