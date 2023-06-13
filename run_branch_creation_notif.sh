#!/bin/sh

if [ ! -f events_cache.txt ]
then
	touch events_cache.txt
fi
output=$(curl -s --header "Authorization: Bearer <GITLAB_TOKEN>" https://gitlab.example.com/api/v4/projects/123/events)

# zsh expands \n within the json into actual newlines if we just do echo "$output", so use printf:
# https://stackoverflow.com/questions/30171582/do-not-interpolate-newline-characters-in-curl-response-in-strings
new_events=$(printf '%s\n' "$output" | jq --slurpfile old events_cache.txt '[$old[][].id] as $old_ids | [.[].id] as $new_ids | ($new_ids - $old_ids) as $new_events | [.[] | select([.id]|inside($new_events))]')
new_branch_creations=$(printf '%s\n' "$new_events" |
  jq -r '
    map(select((.action_name == "pushed new") and (.push_data.action == "created") and (.push_data.ref_type == "branch")))'
)

printf '%s\n' "$output" > events_cache.txt

number_new_branch_creations=$(printf '%s\n' "$new_branch_creations" | jq -r length)
if [ $number_new_branch_creations -gt 0 ]; then
  printf '%s\n' "$new_branch_creations" | jq -c '.[]' | while read i; do
    branch_title=$(printf '%s\n' "$i" |
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
    curl \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{ \"username\": \"reponame GitLab\", \"avatar_url\": \"https://gitlab.example.com/uploads/-/system/appearance/favicon/1/gl-fav.png\", \"embeds\": [{ \"title\": \"$branch_title\", \"url\": \"$branch_url\", \"type\": \"rich\", \"description\": \"\", \"color\": 2697569, \"author\": { \"name\": \"$author_name\", \"icon_url\": \"$author_image\" } }] }" \
      "https://discord.com/api/webhooks/<id>/<token>"
  done
fi
