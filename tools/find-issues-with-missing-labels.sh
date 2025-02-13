#!/bin/bash

# When the repository labels are changed (i.e dropped a label, added a label, etc), you should make the same change to the lists below.
# For example, if the repository added a "type:task" type label, then add "-label:type:task" to the TYPE_LABELS_FILTER.

PRIORITY_LABELS_FILTER='-label:priority-1-critical -label:priority-2-high -label:priority-3-medium -label:priority-4-low'
ISSUE_TYPE_FILTER='-type:Bug -type:Feature -type:Task'

HAS_ISSUES=false

ISSUE_BODY="# Label check action\n"

REPO='renovatebot/renovate'

ISSUE_TITLE="Issues with missing labels"

for FILTER in "$PRIORITY_LABELS_FILTER" "$ISSUE_TYPE_FILTER"; do
    # Extract the label type from the filter
    TYPE=$(echo "$FILTER" | cut -d ':' -f 2 | cut -d '-' -f 1)
    
    # Fetch issues that match the filter
    ISSUES=$(gh issue list --repo $REPO --limit 100000 -s open -S "$FILTER" --json "number,title") || { echo "Failed to fetch issues without $TYPE"; exit 1; }
    # Ignore the Issue from the "Find issues with missing labels" Action
    ISSUES=$(echo "$ISSUES" | jq --arg title "$ISSUE_TITLE" 'map(select(.title != $title))')
    
    if [ "$ISSUES" != "[]" ]; then
        HAS_ISSUES=true
        
        # Create a list of issue numbers
        FORMATTED_OUTPUT=$(echo "$ISSUES" | jq -r '.[].number' | sed 's/^/- https:\/\/redirect.github.com\/renovatebot\/renovate\/issues\//')
        
        # Count the issues and decide if the output should be singular or plural
        ISSUE_COUNT=$(echo "$ISSUES" | jq '. | length')
        ISSUE_SINGULAR_PLURAL=$(if [ "$ISSUE_COUNT" -eq 1 ]; then echo "issue"; else echo "issues"; fi)
        
        # Append the "list of issues without labels" to the issue body
        ISSUE_BODY="$ISSUE_BODY## Found $ISSUE_COUNT $ISSUE_SINGULAR_PLURAL missing \`$TYPE:\`:\n$FORMATTED_OUTPUT\n"
    fi
done

if [ "$HAS_ISSUES" = false ]; then
    echo "All checked issues have labels and type."
    ISSUE_BODY="$ISSUE_BODY All checked issues are correctly labeled and have a type.\n"
fi

LABEL_CHECK_ISSUE_EXISTS=$(gh search issues --repo $REPO --json "number,author,title" | jq --arg title "$ISSUE_TITLE" 'map(select(.title == $title and .author.type == "Bot"))') || { echo "Failed to fetch existing label check issue"; exit 1; }
ISSUE_NUMBER=$(echo "$LABEL_CHECK_ISSUE_EXISTS" | jq -r '.[].number')

if [ -z "$ISSUE_NUMBER" ]; then
    
    # Create a new issue (with the list of issues in it).
    gh issue create --repo $REPO --title "$ISSUE_TITLE" --body "$(echo -e "$ISSUE_BODY")" || { echo "Failed to create issue."; exit 1; }
else
    # Edit the open issue, and update the list of issues.
    gh issue edit "$ISSUE_NUMBER" --repo $REPO --title "$ISSUE_TITLE" --body "$(echo -e "$ISSUE_BODY")" || { echo "Failed to update issue."; exit 1; }
    
    # Re-open the issue.
    gh issue reopen "$ISSUE_NUMBER" --repo $REPO || { echo "Failed to reopen issue"; exit 1; }
fi

if [ "$HAS_ISSUES" = false ]; then
    exit 0
fi

# Show the list of "issues with missing labels" in the logs.
echo -e "$ISSUE_BODY"

# Log a message and "fail" the Action if there are issues with missing labels
echo "Found issues without labels. Please check the issue(s) listed above. Exiting the action."

exit 1

