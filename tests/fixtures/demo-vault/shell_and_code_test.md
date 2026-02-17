---
tags:
  - test
  - shell-test
---

# Shell and Inline Code Test

This note tests that bash conditionals and inline-code wikilinks are not
extracted as real wikilinks by the scanner.

## Real wikilinks (should be extracted)

See [[test_note]] for details.
Also check [[README]] and [[Project/My new masterpeace]].

## Bash conditionals (should NOT be extracted)

Here is a bash script snippet:

```bash
if [[ -d "$TARGET_PATH" ]]; then
    echo "exists"
fi

if [[ ! -f "$HOME/.config" ]]; then
    echo "missing"
fi

[[ "$var" =~ ^[0-9]+$ ]] && echo "is number"
```

The above is inside a fenced code block — already skipped.

But sometimes people write inline bash like `[[ -d "$path" ]]` or mention
the test syntax `[[ ! -f "$file" ]]` in a sentence.

Unfenced bash on its own line (rare but happens in docs):
[[ -d "$MOUNT_POINT" ]] && mount_drive
[[ ! "$title" =~ ^[A-Z] ]] && fix_title

## Inline code wikilinks (should NOT be extracted)

You can reference a link like `[[some note]]` in inline code.
Double backtick example: ``[[another note]]`` should also be skipped.
Mixed: here is `code with [[embedded link]] inside` backticks.

## Inline code tags (should NOT be extracted)

The tag `#not-a-tag` inside backticks should be skipped.
But #real-tag outside should be extracted.

## Real tags at end

#shell-syntax #inline-code-test
