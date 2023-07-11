#!/bin/bash
set -eou pipefail
IFS=$'\n\t'

readonly THIS_REPO="pantheon-systems/plugin-pipeline-example"
readonly DEPENDENCIES_YML="./dependencies.yml"
#####
# Sample dependencies.yml
# ---
# dependencies:
#   yq:
#     current_tag: v4.32.2
#     repo: mikefarah/yq
#####
main() {
	for NAME in $(yq '.dependencies | to_entries | .[].key'  dependencies.yml); do
		echo "Checking ${NAME}"

		local CURRENT_TAG
		CURRENT_TAG="$(yq ".dependencies.${NAME}.current_tag" ${DEPENDENCIES_YML})"
		echo "Current Tag: ${CURRENT_TAG}"

		local REPO
		REPO="$(yq ".dependencies.${NAME}.repo" ${DEPENDENCIES_YML})"

		local LATEST_TAG
		LATEST_TAG="$(gh release view -R "${REPO}" --json tagName -q .tagName)"
		echo "Latest Tag: ${LATEST_TAG}"

		# We likely don't even need to version compare, just ==
		if [[ "${CURRENT_TAG}" == "${LATEST_TAG}" ]];then
			continue
		fi

		local PR_TITLE_BASE="Bump ${REPO} from ${CURRENT_TAG}"
		local PR_TITLE="${PR_TITLE_BASE} to ${LATEST_TAG}"

		LIST_OF_PRS="$(gh pr list -R "${THIS_REPO}" \
			-l dependencies --json title,closed,number | jq -c)"

		local NUMBER_TO_CLOSE_LATER=""
		for PR in $(jq -c '.[]'<<<"${LIST_OF_PRS}"); do
			echo "${PR}"
			if [[ "$(jq -cr .title<<<"${PR}")" == "${PR_TITLE}" ]];then
				# This captures open PRs, or PRs closed without merging
				echo "PR Already Created"
				continue 2
			fi

			if [[ "$(jq -cr .title<<<"${PR}")" == "${PR_TITLE_BASE}"* && "$(jq -cr .closed<<<"${PR}")" == "false" ]];then
				echo "PR for a Previous version exists"
				NUMBER_TO_CLOSE_LATER="$(jq -cr .number<<<"${PR}")"
				echo "${NUMBER_TO_CLOSE_LATER}"
				break
			fi
		done

		BRANCH=DEPS-$(date +%s%N)
		git checkout -b "${BRANCH}"
		yq  -i ".dependencies.${NAME}.current_tag = \"${LATEST_TAG}\"" "${DEPENDENCIES_YML}"
		git add "${DEPENDENCIES_YML}"
		git commit -m "$PR_TITLE"
		git push origin "${BRANCH}"

		PR_BODY="Bumps [${NAME}](https://github.com/${REPO}/releases/tag/${LATEST_TAG}) from ${CURRENT_TAG} to ${LATEST_TAG}."
		NEW_PR=$(gh pr create -l dependencies,automation -t "${PR_TITLE}" -b "${PR_BODY}" -R "${THIS_REPO}")

		git checkout -

		if [[ -n "${NUMBER_TO_CLOSE_LATER}" ]]; then
			echo "Closing old PR #${NUMBER_TO_CLOSE_LATER}"
			gh pr close "${NUMBER_TO_CLOSE_LATER}" -R "${THIS_REPO}" -c "Closing in favor of ${NEW_PR}"
		fi
		echo
	done
	echo "✨ Done"
}

main