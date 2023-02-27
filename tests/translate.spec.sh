#!/usr/bin/env bash

languages=(en fr de)
app_name='TestApp'
script='../bin/polyglot'
file_name='Localizable.strings'
other_source='Other.strings'
tenant_token='f233f89a-7868-4e53-854c-9fa60f5b283e'
translations_path="../$app_name/Extra"
api_url='https://api.dev.polyglot.rocks'
product_id='test.bash.app'
base_file="$translations_path/en.lproj/$file_name"
export PROJECT_NAME='test.app'

cache_root="/tmp"
if [ -n "$GITHUB_HEAD_REF" ]; then
    cache_root="./tmp"
fi

local_env_init() {
    rm -rf "$translations_path"

    for lang in ${languages[@]}; do
        path="$translations_path/$lang.lproj";
        mkdir -p "$path";
        echo "" > "$path/$file_name"
        echo "" > "$path/$other_source"
    done

    rm -rf "$cache_root/$PROJECT_NAME"
    echo '"Cancel" = "Cancel";
// some comment
"Saved successfully" = "Saved successfully";
"4K" = "4K";
"Loading" = "Loading...";' > $base_file
    echo '"Loading" = "Loading...";' > "$translations_path/fr.lproj/$file_name"
    echo '"4K" = "4K";' > "$translations_path/fr.lproj/$file_name"
    echo '"Loading" = "custom-translation";' > "$translations_path/de.lproj/$file_name"
}

clear_db() {
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Cancel" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Loading" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Saved successfully" -s >> /dev/null
}

add_manual_translations() {
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/Cancel" -d "{ \"translations\": { \"en\": \"Cancel\", \"de\": \"de-manual-test\", \"fr\": \"fr-manual-test\" } }" -s >> /dev/null
}

setup_suite() {
    clear_db "$product_id"
    local_env_init
}

setup() {
    export PRODUCT_BUNDLE_IDENTIFIER=$product_id
    export PROJECT_NAME='test.app'
}

test_token_not_specified() {
    assert_equals "`$script`" 'Tenant token is required as a first argument'
}

test_product_id_not_specified() {
    export PRODUCT_BUNDLE_IDENTIFIER=''
    result=`$script $tenant_token ../$app_name`
    assert_equals "$result" 'Product id is not specified. Use $PRODUCT_BUNDLE_IDENTIFIER for this'
}

test_invalid_tenant_token() {
    assert_equals "`$script 11111 ../$app_name`" 'Invalid tenant token'
}

test_clear_cache_error() {
    export PROJECT_NAME=''
    result=`$script --clear-cache`
    assert_equals "$result" 'Project name is not specified. Set $PROJECT_NAME or pass "./" to it'
}

test_clear_cache() {
    add_manual_translations
    output=`$script $tenant_token ../$app_name`
    output=`$script --clear-cache`

    cache_path=`find $cache_root/$PROJECT_NAME -name ".last_used_manual_translations" | head -1`
    cache_content=`cat "$cache_path"`
    assert_equals "$cache_content" '{}'
}

test_found_duplicates() {
    base_file_content=`cat $base_file`
    echo '"Loading" = "Loading...";' >> $base_file
    output="`$script $tenant_token ../$app_name`"
    is_found_duplicates=`echo "$output" | grep -c 'Found duplicates'`
    assert_equals $is_found_duplicates 1
    echo "$base_file_content" > $base_file
}

test_auto_translation() {
    setup_suite
    bash $script $tenant_token ../$app_name
    translation=`grep 'Cancel' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    custom_translation=`grep 'Loading' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    marked_translation=`grep '4K' $translations_path/fr.lproj/$file_name | cut -d '=' -f 2`
    assert_equals $translation '"Abbrechen";'
    assert_equals ' "4K"; //' "$marked_translation"
    assert_equals $custom_translation '"custom-translation";'
}

test_load_manual_translations() {
    add_manual_translations

    if [ -z "$1" ]; then
        local_env_init
    fi

    output=`$script $tenant_token ../$app_name`
    translation=`grep 'Cancel' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    assert_equals $translation '"de-manual-test";'
}

test_replace_auto_translations_with_manual() {
    setup_suite
    test_auto_translation
    test_load_manual_translations 'no-clear'
}

test_translations_from_other_file() {
    cp $base_file $translations_path/en.lproj/$other_source
    echo '"Now" = "Now";' >> $translations_path/en.lproj/$other_source

    output=`$script $tenant_token ../$app_name $other_source`
    translation=`grep 'Now' $translations_path/fr.lproj/$other_source | cut -d '=' -f 2`
    assert_equals "$translation" ' "À présent";'
}

test_do_nothing_without_updates() {
    output=`$script $tenant_token ../$app_name`
    output=`$script $tenant_token ../$app_name`
    output="`$script $tenant_token ../$app_name`"
    translation_count=`grep -c 'Loading' $translations_path/de.lproj/$file_name`
    files_without_changes=`echo "$output" | grep -c 'seems to be translated already'`
    assert_equals $files_without_changes 2
    assert_equals $translation_count 1
}
