#!/bin/sh

if [ ! -f commits_master_cache.txt ]
then
	touch commits_master_cache.txt
fi
output=$(curl -s --header "Authorization: Bearer <GITLAB_TOKEN>" https://gitlab.example.com/api/v4/projects/123/repository/commits?per_page=100)

# zsh expands \n within the json into actual newlines if we just do echo "$output", so use printf:
# https://stackoverflow.com/questions/30171582/do-not-interpolate-newline-characters-in-curl-response-in-strings
new_commits=$(printf '%s\n' "$output" | jq --slurpfile old commits_master_cache.txt '[$old[][].id] as $old_ids | [.[].id] as $new_ids | ($new_ids - $old_ids) as $new_commits | [.[] | select([.id]|inside($new_commits))]')
printf '%s\n' "$output" > commits_master_cache.txt

number_new_commits=$(printf '%s\n' "$new_commits" | jq -r length)
if [ $number_new_commits -gt 0 ]; then
	author_field=$(printf '%s\n' "$new_commits" |
		jq -r '
		([.[].author_name] | unique) as $authors
		| $authors
		| if length > 2 then ("\($authors[0]) and \(length - 1) others") else if length > 1 then ("\($authors[0]) and \($authors[1])") else $authors[0] end end'
	)
	author_image=$(curl -s --header "Authorization: Bearer <GITLAB_TOKEN>" \
		"$(printf '%s\n' "$new_commits" |
		jq -r '
		([.[].author_email] | unique) as $emails
		| @uri "https://gitlab.example.com/api/v4/avatar?email=\($emails[0])"'
		)" | jq -r .avatar_url )
	headline=$(printf '%s\n' "$new_commits" |
		jq -r '
		"\(length) new commit\(if length > 1 then "s" else "" end)"'
	)
  headline_link=$(printf '%s\n' "$new_commits" |
    jq -r '
    if length > 1 then "https://gitlab.example.com/dept/user/reponame/-/compare/\(if (.[0].parent_ids | length) > 1 then .[0].parent_ids[0] else .[-1].parent_ids[0] end)...\(.[0].short_id)?straight=false" else .[0].web_url end
    '
  )
	body=$(printf '%s\n' "$new_commits" |
		jq -r '
		[reverse | .[] | "[`\(.short_id)`](\(.web_url)) \(.title) - \(.committer_name)"] as $list | $list | .[0:5] | join("\\n") as $string | $list | if length > 5 then "\($string)\\n   ...and \(length - 5) more" else $string end
		'
	)

  body=$(printf '%s\n' "$body" | sed 's/"/\\\"/g')

	curl \
		-X POST \
		-H "Content-Type: application/json" \
		-d "{ \"username\": \"reponame GitLab\", \"avatar_url\": \"https://gitlab.example.com/uploads/-/system/appearance/favicon/1/gl-fav.png\", \"embeds\": [{ \"title\": \"[master] $headline\", \"url\": \"$headline_link\", \"type\": \"rich\", \"description\": \"$body\", \"color\": 2697569, \"author\": { \"name\": \"$author_field\", \"icon_url\": \"$author_image\" } }] }" \
    "https://discord.com/api/webhooks/<id>/<token>"
fi
