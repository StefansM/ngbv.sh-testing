#!/bin/bash

current_dir="$(readlink -f "$(dirname "${BASH_SOURCE[0]}")")"
nbgv="$current_dir/nbgv.sh"

export GIT_CEILING_DIRECTORIES="$current_dir"

fail() {
    echo "fail: $1" >&2
}


make-test-dir() {
    [[ -z "$1" ]] && return 1
    [[ -e "$1" ]] && rm -rf "$1"

    mkdir "$1"
    cd "$1" || exit 1
}


test-no-git-repo() {
    make-test-dir "${FUNCNAME[0]}"

    if "$nbgv" &>/dev/null; then
        fail "nbgv should abort outside of a git repo."
        return 1
    fi
}

test-no-version-txt() {
    make-test-dir "${FUNCNAME[0]}"

    git init -q

    if "$nbgv" &>/dev/null; then
        fail "nbgv should abort if no version.txt is present."
        return 1
    fi
}

test-version-txt-has-not-been-comitted() {
    make-test-dir "${FUNCNAME[0]}"

    git init -q

    touch ignore
    git add ignore
    git commit -q -m 'Add file'

    echo "0.0.0" > version.txt
    if "$nbgv" &>/dev/null; then
        fail "nbgv should abort if version.txt is not comitted."
        return 1
    fi
}

test-committed-version-used-verbatim() {
    make-test-dir "${FUNCNAME[0]}"

    expected="0.6.9"

    git init -q

    echo "$expected" > version.txt
    git add version.txt
    git commit -q -m 'Add file'

    if ! version="$("$nbgv")"; then
        fail "nbgv should succeed when version.txt is committed."
        return 1
    fi

    if [[ "$version" != "$expected" ]]; then
        fail "version was '$version', expected '$expected'."
        return 1
    fi
}

test-patch-version-is-incremented-per-commit() {
    make-test-dir "${FUNCNAME[0]}"

    input="0.1.0"
    expected="0.1.2"

    git init -q

    echo "$input" > version.txt
    git add version.txt
    git commit -q -m 'Add version.txt'

    echo 1 > ignored
    git add ignored
    git commit -q -m 'Commit 1'

    echo 2 > ignored
    git add ignored
    git commit -q -m 'Commit 2'

    if ! version="$("$nbgv")" 2>/dev/null; then
        fail "nbgv should succeed when version.txt is committed."
        return 1
    fi

    if [[ "$version" != "$expected" ]]; then
        fail "version was '$version', expected '$expected'."
        return 1
    fi
}

test-suffix-is-added-on-non-default-branches() {
    make-test-dir "${FUNCNAME[0]}"

    input="0.1.0"
    expected="0.1.2"

    git init -q

    echo "$input" > version.txt
    git add version.txt
    git commit -q -m 'Add version.txt'

    git checkout -q -b nondefault

    echo 1 > ignored
    git add ignored
    git commit -q -m 'Commit 1'


    if ! version="$("$nbgv")" 2>/dev/null; then
        fail "nbgv should succeed when version.txt is committed."
        return 1
    fi

    case "$version" in
        *-dev)
            return 0
            ;;
        *)
            fail "nbgv should add a suffix when on a non-default branch."
            return 1
            ;;
    esac
}

test-arbitrary-default-branches-supported() {
    make-test-dir "${FUNCNAME[0]}"

    git init -q --initial-branch some-branch

    input="0.0.1"

    echo "$input" > version.txt
    git add version.txt
    git commit -q -m 'Add version.txt'

    git checkout -q -b nondefault

    echo 1 > ignored
    git add ignored
    git commit -q -m 'Commit 1'


    export MAIN_BRANCH=some-branch
    if ! version="$("$nbgv")" 2>/dev/null; then
        fail "nbgv should succeed when version.txt is committed."
        return 1
    fi

    case "$version" in
        *-dev)
            return 0
            ;;
        *)
            fail "nbgv should add a suffix when on a non-default branch."
            return 1
            ;;
    esac
}

test-unparseable-versions-are-errors() {
    input="$1"
    make-test-dir "${FUNCNAME[0]}"

    git init -q

    echo "$input" > version.txt
    git add version.txt
    git commit -q -m 'Add version.txt'

    if "$nbgv" &>/dev/null; then
        fail "nbgv should fail when given an incompatible version."
        return 1
    fi
}

test-do-not-support-multiple-roots() {
    make-test-dir "${FUNCNAME[0]}"

    git init -q

    input="0.0.0"

    echo "$input" > version.txt
    git add version.txt
    git commit -q -m 'Add version.txt'

    git checkout -q --orphan orphan

    echo "1" > orphan_file
    git add orphan_file
    git commit -q -m "Orphan commit"

    git checkout -q master
    git merge -q -m 'Merge histories' --allow-unrelated-histories orphan


    if "$nbgv" &>/dev/null; then
        fail "nbgv should fail when multiple roots are present."
        return 1
    fi
}

failures=0
( test-no-git-repo ) || failures=$((failures + 1))
( test-no-version-txt ) || failures=$((failures + 1))
( test-version-txt-has-not-been-comitted ) || failures=$((failures + 1))
( test-committed-version-used-verbatim ) || failures=$((failures + 1))
( test-patch-version-is-incremented-per-commit ) || failures=$((failures + 1))
( test-suffix-is-added-on-non-default-branches ) || failures=$((failures + 1))
( test-arbitrary-default-branches-supported ) || failures=$((failures + 1))
( test-do-not-support-multiple-roots ) || failures=$((failures + 1))

invalid_inputs=("" "0.1" "foo.1.2")
for invalid_input in "${invalid_inputs[@]}"; do
    ( test-unparseable-versions-are-errors "$invalid_input" ) || failures=$((failures + 1))
done

if [[ "$failures" -ne 0 ]]; then
    echo "There were $failures test failures." >&2
    exit 1
fi
echo "All tests successful."
