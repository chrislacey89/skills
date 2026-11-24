# Dependencies in a throwaway copy

This file is the canonical statement of how a throwaway `git archive` copy gets
the dependencies its test command needs, and of the check that the copy runs its
own source. `/fix-findings` points at it for the breaker's copy, and
`differential-check.md` points at it for the base copy. Neither restates it.

## Link or install

A `git archive` copy holds tracked files only. The ignored files the test command
needs are not in it: config such as `.env.local` and its siblings, and the
dependency tree. Copy the config files; they are read as values.

For the dependency tree there are two ways in, and only one is always sound:

- **Run the project's install command inside the copy.** The tree is then the
  copy's own, and its loader finds the copy's source.
- **Link the original checkout's tree into the copy.** This is sound only when
  the tree's loader does not work out where the project's own source lives from
  its own real path. Some loaders do: they build the project's source paths from
  the location of their own files, and through a link that location resolves to
  the original checkout. The copy then runs the original checkout's source, not
  the commit it was extracted from, and every result looks normal. PHP is one
  such case: `__DIR__` is the directory of the file "with symlinks resolved"
  ([PHP magic constants](https://www.php.net/manual/en/language.constants.magic.php)),
  and the autoload files Composer generates build the project's source paths
  from it.

When you cannot tell which kind of loader the project uses, install. Do not
work around a resolving loader by copying part of the tree and linking the rest:
which parts would have to be copied is that tool's own behavior, and a wrong
guess either still runs the original's source or fails to load at all.

## Check where the source resolves, before the first run

Whichever way the tree came in, run this block before the first command that
runs code in the copy (the breaker's control, the differential check's base
run). It asks the loader where it found one project source file that the test
loads, and fails unless that path is inside the copy.

Set `COPY` to the copy's path, as its block printed it. Replace the placeholder
line between the `PROBE_END` lines with a command, run from the copy, whose last
line of output is the path the loader resolved that file to. The heredoc is
quoted, so the command goes in as written, with any single or double quotes and
`$`. Both `PROBE_END` lines must start at column 0: pasted indented, the heredoc
never closes and swallows the rest of the block, so the block's `EXIT` trap
fails it with `copy check failed: the block did not run to its end`. Take the command from the stack's own documentation of how to ask where a
class or module was loaded from. The probe has to go through the same loader the
test command uses: a probe that looks the file up some other way
(`realpath src/Foo.php`, `ls`) reports the copy's file whatever the loader does,
and proves nothing.

<!-- copy-check: source-location -->
```bash
COPY="<the copy's path, as its block printed it>"
DONE=0
trap 'rc=$?; [ "$rc" -ne 0 ] || [ "$DONE" = 1 ] || { echo "copy check failed: the block did not run to its end (is PROBE_END at column 0?)" >&2; exit 1; }' EXIT
{ PROBE=$(cat); } <<'PROBE_END'
<a command, run from the copy, whose last line is the path the loader resolved one project source file to>
PROBE_END
REAL_COPY="$(cd "$COPY" && pwd -P)" || { echo "copy check failed: cannot enter $COPY" >&2; exit 1; }
OUT="$(cd "$REAL_COPY" && sh -c "$PROBE")" || { echo "copy check failed: the probe exited nonzero" >&2; exit 1; }
RESOLVED="$(printf '%s\n' "$OUT" | tr -d '\r' | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//;/^$/d' | tail -n 1)"
[ -n "$RESOLVED" ] || { echo "copy check failed: the probe printed no path" >&2; exit 1; }
case "$RESOLVED" in /*) ;; *) RESOLVED="$REAL_COPY/$RESOLVED" ;; esac
HOPS=0
while :; do
  DIR="$(cd -P "$(dirname "$RESOLVED")" 2>/dev/null && pwd -P)" || { echo "copy check failed: $RESOLVED does not exist" >&2; exit 1; }
  RESOLVED="$DIR/$(basename "$RESOLVED")"
  [ -L "$RESOLVED" ] || break
  HOPS=$((HOPS + 1))
  [ "$HOPS" -le 40 ] || { echo "copy check failed: too many symbolic links resolving $RESOLVED" >&2; exit 1; }
  LINK="$(readlink "$RESOLVED")" || { echo "copy check failed: cannot read the link $RESOLVED" >&2; exit 1; }
  case "$LINK" in /*) RESOLVED="$LINK" ;; *) RESOLVED="$DIR/$LINK" ;; esac
done
[ -f "$RESOLVED" ] || { echo "copy check failed: $RESOLVED is not an existing file" >&2; exit 1; }
DONE=1
case "$RESOLVED" in
  "$REAL_COPY"/*) echo "copy check: the loader resolved $RESOLVED, inside the copy" ;;
  *) echo "copy check failed: the loader resolved $RESOLVED, outside the copy $REAL_COPY" >&2; exit 1 ;;
esac
```

A failure names the path the loader resolved. It means the run would test some
other source than the copy's, so no result from it is about the copy:

- **`/fix-findings` breaker:** report **`not-run`** with the printed line. Do not
  run the control.
- **Differential check:** abort, and say why with the printed line.

To recover, remove the linked tree, run the project's install command inside the
copy, and run the block again.

The block checks one file. It catches a loader that sends the whole project to
the original checkout, which is how a resolving loader fails. It cannot catch a
test that loads one particular file from somewhere else, so pick a file the
check under test actually loads.
