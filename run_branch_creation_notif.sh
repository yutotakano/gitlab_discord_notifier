#!/bin/sh

if [ ! -f events_cache.json ]
then
  touch events_cache.json
fi

webhook_url="https://discord.com/api/webhooks/<guild id>/<webhook id>" # example
output=$(curl -s --header "Authorization: Bearer <gitlab token>" https://gitlab.example.com/api/v4/projects/123/events)

# zsh expands \n within the json into actual newlines if we just do echo "$output", so use printf:
# https://stackoverflow.com/questions/30171582/do-not-interpolate-newline-characters-in-curl-response-in-strings
new_events=$(printf '%s\n' "$output" | jq --slurpfile old events_cache.json '[$old[][].id] as $old_ids | [.[].id] as $new_ids | ($new_ids - $old_ids) as $new_events | [.[] | select([.id]|inside($new_events))]')
new_branch_creations=$(printf '%s\n' "$new_events" |
  jq -r '
    map(select((.action_name == "pushed new") and (.push_data.action == "created") and (.push_data.ref_type == "branch")))'
)
new_branch_deletions=$(printf '%s\n' "$new_events" |
  jq -r '
    map(select((.action_name == "deleted") and (.push_data.action == "removed") and (.push_data.ref_type == "branch")))'
)

printf '%s\n' "$output" > events_cache.json

number_new_branch_creations=$(printf '%s\n' "$new_branch_creations" | jq -r length)
if [ $number_new_branch_creations -gt 0 ]; then
  printf '%s\n' "$new_branch_creations" | jq -c '.[]' | while read i; do
    branch_title=$(printf '%s\n' "$i" | jq -r '.push_data.ref')
    branch_title_text=$(printf '%s\n' "$i" |
      jq -r '
        "Branch `\(.push_data.ref)` newly created by \(.author.name) "'
    )
    branch_url=$(printf '%s\n' "$i" |
      jq -r '"https://gitlab.example.com/dept/user/reponame/-/tree/\(.push_data.ref)"'
    )
    author_name=$(printf '%s\n' "$i" |
      jq -r .author.name
    )
    author_image=$(printf '%s\n' "$i" |
      jq -r '.author.avatar_url'
    )

    # Check number of commits pushed together with the branch creation
    number_commits=$(printf '%s\n' "$i" |
      jq -r '.push_data.commit_count'
    )
    body=""
    if [ $number_commits -eq 1 ]; then
      # No additional request needed, all info is in the original JSON
      body=$(printf '%s\n' "$i" |
        jq -r '
        "[`\(.push_data.commit_to | .[0:8])`](https://gitlab.example.com/dept/user/reponame/-/commit/\(.push_data.commit_to)) \(.push_data.commit_title) - \(.author.name)"'
      )

      # Escape quotes
      body=$(printf '%s\n' "$body" | sed 's/"/\\\"/g')
    elif [ $number_commits -gt 1 ]; then
      # Make an additional request to get the commits between main and to
      # (The .from field is empty in all cases for some reason)
      to_sha=$(printf '%s\n' "$body" | jq -r '.push_data.commit_to')
      new_commits=$(curl -s --header "Authorization: Bearer <gitlab token>" "https://gitlab.example.com/api/v4/projects/123/repository/compare?from=main&to=$to_sha")

      body=$(printf '%s\n' "$new_commits" |
        jq -r '
        [reverse | .commits[] | "[`\(.short_id)`](\(.web_url)) \(.title) - \(.committer_name)"] as $list | $list | .[0:5] | join("\\n") as $string | $list | if length > 5 then "\($string)\\n   ...and \(length - 5) more" else $string end
        '
      )

      # Escape quotes
      body=$(printf '%s\n' "$body" | sed 's/"/\\\"/g')
    fi


    curl \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{ \"username\": \"reponame GitLab\", \"avatar_url\": \"https://gitlab.example.com/uploads/-/system/appearance/favicon/1/gl-fav.png\", \"embeds\": [{ \"title\": \"$branch_title_text\", \"url\": \"$branch_url\", \"type\": \"rich\", \"description\": \"$number_commits commit(s) ahead of \`main\`\n\n$body\", \"color\": 28928, \"author\": { \"name\": \"$author_name\", \"icon_url\": \"$author_image\" } }] }" \
      ${webhook_url}

    # Duplicate the commit tracker
    cp run_main_commit_notif.sh "run_${branch_title}_commit_notif.sh"
    escaped_branch_title=$(printf '%s\n' "$branch_title" | sed -e 's/[\/&]/\\&/g')
    # Replace all ocurences of main with branch name (we assume it's not like space-containing invalid things)
    sed -i "s/main/${escaped_branch_title}/g" run_${branch_title}_commit_notif.sh

    # Call it once manually without sending anything to build the cache
    # The firs commits together with branch creation is kinda briefly done in
    # the above branch notif anyway so we sacrifice those
    ./run_${branch_title}_commit_notif.sh --no-send

    # Add it to crontab
    (crontab -l 2>/dev/null; echo "# Added automatically" && echo "* * * * * cd ~/bot_directory && ./run_${branch_title}_commit_notif.sh") | crontab -
  done
fi


number_new_branch_deletions=$(printf '%s\n' "$new_branch_deletions" | jq -r length)
if [ $number_new_branch_deletions -gt 0 ]; then
  printf '%s\n' "$new_branch_deletions" | jq -c '.[]' | while read i; do
    branch_title=$(printf '%s\n' "$i" | jq -r '.push_data.ref')
    branch_title_text=$(printf '%s\n' "$i" |
      jq -r '
        "🗑️ Branch `\(.push_data.ref)` deleted by \(.author.name)"'
    )
    author_name=$(printf '%s\n' "$i" |
      jq -r .author.name
    )
    author_image=$(printf '%s\n' "$i" |
      jq -r '.author.avatar_url'
    )
    curl \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{ \"username\": \"reponame GitLab\", \"avatar_url\": \"https://gitlab.example.com/uploads/-/system/appearance/favicon/1/gl-fav.png\", \"embeds\": [{ \"title\": \"$branch_title_text\", \"url\": null, \"type\": \"rich\", \"description\": \"\", \"color\": 12137251, \"author\": { \"name\": \"$author_name\", \"icon_url\": \"$author_image\" } }] }" \
      ${webhook_url}

    # Delete the duplicated commit tracker if it exists
    if [ -f run_${branch_title}_commit_notif.sh ] && [ "${branch_title}" != "main" ]; then
      rm run_${branch_title}_commit_notif.sh
    fi
    if [ -f commits_cache_${branch_title}.json ] && [ "${branch_title}" != "main" ]; then
      rm commits_cache_${branch_title}.json
    fi
    # We won't bother with crontab deletion since that can risk deleting other important crontabs
  done
fi
