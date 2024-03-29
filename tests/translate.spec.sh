#!/usr/bin/env bash

languages=(en fr de)
app_name='TestApp'
script='../bin/polyglot'
file_name='Localizable.strings'
other_source='Other.strings'
tenant_token='f233f89a-7868-4e53-854c-9fa60f5b283e'
translations_path="../$app_name/Extra"
api_url='https://api.dev.polyglot.rocks'
api_url=${API_URL:-$api_url}
product_id='test.bash.app'
base_file="$translations_path/en.lproj/$file_name"

exit_code_mark='POLYGLOT_EXIT_CODE'
translation_error_mark="$exit_code_mark: 50"
free_plan_exhausted_mark="$exit_code_mark: 42"

initial_data='"Cancel" = "Cancel";
// polyglot:max_length:10
"Saved successfully" = "Saved successfully";
// some comment = 0
// polyglot:max_length:none
// polyglot:max_length
"4K" = "4K";
"Loading" = "Loading...";
"CUSTOM_STRING" = "Custom";
"disabled_globally = "disabled_completely"; // polyglot:disable:this'

cache_root="/tmp"
if [ -n "$GITHUB_HEAD_REF" ]; then
    cache_root="./tmp"
fi

local_env_init() {
    rm -rf "$translations_path"

    for lang in ${languages[@]}; do
        path="$translations_path/$lang.lproj";
        mkdir -p "$path";
        echo "$initial_data" > "$path/$file_name"
        echo "" > "$path/$other_source"
    done

    rm -rf "$cache_root/$product_id"
    echo '"Loading" = "custom-translation";
"CUSTOM_STRING" = "disabled"; // polyglot:disable:this
"disabled_globally = "this-shouldnt-change";' > "$translations_path/de.lproj/$file_name"
}

clear_db() {
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/CHANGED_STRING" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/CUSTOM_STRING" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Cancel" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Loading" -s >> /dev/null
    curl -X DELETE -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$1/strings/Saved successfully" -s >> /dev/null
}

add_manual_translations() {
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/CUSTOM_STRING" -d "{ \"translations\": { \"en\": \"Custom\", \"de\": \"de-custom-test\", \"fr\": \"fr-custom-test\" } }" -s >> /dev/null
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/disabled_globally" -d "{ \"translations\": { \"en\": \"disabled_completely\" } }" -s >> /dev/null
    # make sure we create auto translations
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/Cancel" -d "{ \"translations\": { \"en\": \"Cancel\" } }" -s >> /dev/null
    # then populate manual translations
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/Cancel" -d "{ \"translations\": { \"en\": \"Cancel\", \"de\": \"de-manual-test\", \"fr\": \"fr-manual-test\" }, \"translatorComment\": \"Need too more context!\" }" -s >> /dev/null
}

add_manual_translation() {
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/$1" -d "{ \"translations\": { \"en\": \"$1\", \"de\": \"de-$1-test\", \"fr\": \"fr-$1-test\" }, \"description\": \"$2\" }" -s >> /dev/null
}

setup_suite() {
    clear_db "$product_id"
    local_env_init
}

setup() {
    export PRODUCT_BUNDLE_IDENTIFIER=$product_id
}

test_token_not_specified() {
    assert_equals 1 "`$script | grep -c 'Tenant token is required as a first argument'`"
}

test_product_id_not_specified() {
    export PRODUCT_BUNDLE_IDENTIFIER=''
    result=`$script $tenant_token -p ../$app_name | grep -v WARN`
    assert_equals "$result" 'Product id is not specified. Use $PRODUCT_BUNDLE_IDENTIFIER for this'
}

test_invalid_tenant_token() {
    assert_equals 1 "`$script 11111 -p ../$app_name | grep -c 'Invalid tenant token'`"
}

test_clear_cache_error() {
    export PRODUCT_BUNDLE_IDENTIFIER=''
    result=`$script --clear-cache | grep -v WARN`
    assert_equals "$result" 'Product id is not specified. Use $PRODUCT_BUNDLE_IDENTIFIER for this'
}

test_clear_cache() {
    add_manual_translations
    output=`$script $tenant_token -p ../$app_name`
    output=`$script --clear-cache`

    cache_path=`find $cache_root/$product_id -name ".last_used_manual_translations" | head -1`
    cache_content=`cat "$cache_path"`
    assert_equals "$cache_content" '{}'
}

test_found_duplicates() {
    base_file_content=`cat $base_file`
    echo '"Loading" = "Loading...";' >> $base_file
    output="`$script $tenant_token -p ../$app_name`"
    is_found_duplicates=`echo "$output" | grep -c 'Found duplicates'`
    assert_equals $is_found_duplicates 1
    echo "$base_file_content" > $base_file
}

test_auto_translation() {
    setup_suite
    output="`$script $tenant_token -p ../$app_name`"
    translation=`grep 'Cancel' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    length_limited_translation=`grep 'Saved successfully' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    custom_translation=`grep 'Loading' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    marked_translation=`grep '4K' $translations_path/fr.lproj/$file_name | cut -d '=' -f 2`
    description=`curl -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/4K" -s | jq -r '.description'`

    assert_multiple "Stornieren" "Abbrechen" "$translation"
    assert_multiple '"Gespeichert.";' '"Erfolgreich";' '"Gespeichert";' "$length_limited_translation"
    assert_equals ' "4K"; // translation is identical to the English string' "$marked_translation"
    assert_equals '"custom-translation";' $custom_translation
    assert_equals 'some comment = 0' "$description"
}

test_load_manual_translations() {
    add_manual_translations

    if [ -z "$1" ]; then
        local_env_init
    fi

    output=`$script $tenant_token -p ../$app_name -d '   '`
    translation=`grep 'Cancel' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    assert_equals "$translation" ' "de-manual-test"; // translator comment: "Need too more context!"'
    translation=`grep 'disabled_globally' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    assert_equals $translation '"this-shouldnt-change";'

    custom_translation=`grep 'CUSTOM_STRING' $translations_path/fr.lproj/$file_name | cut -d '=' -f 2`
    assert_equals "$custom_translation" ' "fr-custom-test"; // corrected by a human'
    custom_translation=`grep 'CUSTOM_STRING' $translations_path/de.lproj/$file_name | sed -e 's/;[ 	]*\/\/.*/;/' | cut -d '=' -f 2`
    assert_equals $custom_translation '"disabled";'
}

test_replace_auto_translations_with_manual() {
    setup_suite
    test_auto_translation
    test_load_manual_translations 'no-clear'
}

test_translations_from_other_file() {
    cp $base_file $translations_path/en.lproj/$other_source
    echo '"Now" = "Now";' >> $translations_path/en.lproj/$other_source

    output=`$script $tenant_token -p ../$app_name -f $other_source`
    translation=`grep 'Now' $translations_path/fr.lproj/$other_source | cut -d '=' -f 2`

    assert_equals ' "Maintenant";' "$translation"
}

test_error_on_invalid_extension() {
    output=`$script $tenant_token -p ../$app_name -f "Localizable.strings,Main.storyboard"`
    found_error=`echo "$output" | grep "'Main.storyboard' is not a .strings file"`
    assert_not_equals "" "$found_error"
}

# test_do_nothing_without_updates() {
#     output=`$script $tenant_token -p ../$app_name`
#     output=`$script $tenant_token -p ../$app_name`
#     output="`$script $tenant_token -p ../$app_name`"
#     translation_count=`grep -c 'Loading' $translations_path/de.lproj/$file_name`
#     files_without_changes=`echo "$output" | grep -c 'seems to be translated already'`
#     assert_equals $files_without_changes 2
#     assert_equals $translation_count 1
# }

test_add_new_language() {
    rm -rf "$cache_root/$product_id"
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id" -d "{ \"languages\": [ \"en\"] }" -s
    path="$translations_path/ru.lproj";
    mkdir -p "$path";
    echo "" > "$path/$file_name"
    output=`$script $tenant_token -p ../$app_name`
    translation=`grep 'Cancel' $path/$file_name | cut -d '=' -f 2`

    assert_multiple "Отменить" "Отмена" "$translation"
}

test_base_is_not_included() {
    base_path="$translations_path/Base.lproj"
    mkdir "$base_path"
    touch "$base_path/Localizble.strings"
    output=`$script $tenant_token -p ../$app_name`
    found_base=`echo "$output" | grep "Found languages:" | grep -o Base`
    rm -rf "$base_path"
    assert_equals "" "$found_base"
}

test_translate_equal_strings_when_equal_line_count() {
    setup_suite
    # x2 launch for getting manual_translations_changed == false
    output=`$script $tenant_token -p ../$app_name`
    output=`$script $tenant_token -p ../$app_name`

    path="$translations_path/fr.lproj/$file_name";
    echo "$initial_data" | head -4 > $path
    echo '"Loading" = "custom-translation";' >> $path
    output=`$script $tenant_token -p ../$app_name`
    translation=`grep 'Cancel' $path | cut -d '=' -f 2`
    custom_translation=`grep 'Loading' $path | cut -d '=' -f 2`
    assert_equals ' "Annuler";' "$translation"
    assert_equals ' "custom-translation";' "$custom_translation"
}

test_remove_duplicates_from_lang_files() {
    path="$translations_path/fr.lproj/$file_name";
    echo "$initial_data" > $path
    echo '"4K" = "4K";' >> $path
    echo '"4K" = "4K";' >> $path
    output=`$script $tenant_token -p ../$app_name`
    translations_count=`grep -c '4K' $path`
    assert_equals 1 "$translations_count"
}

test_remove_deleted_strings_from_lang_files() {
    path="$translations_path/fr.lproj/$file_name";
    removed_lines='"DELETED" = "deleted str";
"Unused" = "DELETED";'
    echo "$removed_lines" >> $path
    disabled_lines='"disabled_globally = "this-shouldnt-change";';
    echo "$disabled_lines" >> $path
    output=`$script $tenant_token -p ../$app_name`
    removed_lines_count=`grep -c "$removed_lines" $path`
    assert_equals 0 $removed_lines_count
    disabled_lines_count=`grep -c "$disabled_lines" $path`
    assert_equals 1 $disabled_lines_count
}

test_use_complex_comment() {
    path="$translations_path/en.lproj/$file_name";
    NL=$'\n'
    complex_comment='// some|~|text
   //complex "comment!@#$%^&*")
	//  serious: case'
    str='"complex_str" = "complex string";'
    echo "$initial_data${NL}$complex_comment${NL}$str" > $path
    output=`$script $tenant_token -p ../$app_name`
    description=`curl -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/complex_str" -s | jq -r '.description'`
    descr_from_comment=`echo "$complex_comment" | sed -e 's/[ 	]*\/\/[ ]*//g' -e 's/"/\\\"/g'`
    escaped_descr=`echo "$description" | sed -e 's/"/\\\"/g'`

    assert_equals 3 `echo "$escaped_descr" | wc -l`
    assert_equals "$descr_from_comment" "$escaped_descr"
}

test_translate_string_with_spec_chars() {
    path="$translations_path/en.lproj/$file_name";
    echo '"with_spec_chars" = "string with\nspecial\n \"chars\", now";' > $path
    output=`$script $tenant_token -p ../$app_name`
    translation=`grep 'with_spec_chars' $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    assert_multiple ' "Zeichenfolge mit\nspeziellen\n\"Zeichen\", jetzt";' ' "Zeichenkette mit\nspeziellen\n \"Zeichen\", jetzt";' ' "Zeichenkette mit\nspeziellem\n \"Zeichen\", jetzt";' ' "Seil mit\nspeziell\n \"Zeichen\", jetzt";' ' "Seil mit\nspeziellen\n \"Zeichen\", jetzt";' "$translation"
}

test_restart_translation_if_descr_changed() {
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/fork" -d "{ \"translations\": { \"en\": \"fork\", \"fr\": \"fourche\", \"de\": \"gabel\" }, \"description\": \"working with the Github repository\" }" -s >> /dev/null
    path="$translations_path/en.lproj/$file_name";
    str_with_comment='// cutlery
"fork" = "fork";'
    echo "$str_with_comment" > $path
    output=`$script $tenant_token -p ../$app_name`
    translation=`grep 'fork' $translations_path/fr.lproj/$file_name | cut -d '=' -f 2`
    description=`curl -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/fork" -s | jq -r '.description'`
    assert_equals ' "fourchette";' "$translation"
    assert_equals 'cutlery' "$description"
}

test_restart_translation_if_max_len_changed() {
    str_id='change_max_len_str'
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/$str_id" -d "{ \"translations\": { \"en\": \"Not enough memory on your device\", \"fr\": \"Mémoire insuffisante sur votre appareil\", \"de\": \"Nicht genügend Speicher auf Ihrem Gerät\" }, \"desiredMaxLength\": 30 }" -s >> /dev/null
    path="$translations_path/en.lproj/$file_name";
    str_with_max_len="// polyglot:max_length:12
\"$str_id\" = \"Not enough memory on your device\";"
    echo "$str_with_max_len" > $path
    output=`$script $tenant_token -p ../$app_name`
    translation=`grep "$str_id" $translations_path/de.lproj/$file_name | cut -d '=' -f 2`
    max_len=`curl -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/$str_id" -s | jq -r '.desiredMaxLength'`
    assert_multiple ' "Nicht genug Speicher.";' ' "Nicht genug Speicher";' ' "Zu wenig Speicher";' "$translation"
    assert_equals 12 $max_len
}

test_restart_translation_if_src_str_changed() {
    fr_path="$translations_path/fr.lproj/$file_name";
    old_fr_value='Old-fr-value'
    curl -X PUT -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/CHANGED_STRING" -d "{ \"translations\": { \"en\": \"Old-value\", \"fr\": \"$old_fr_value\", \"de\": \"Old-de-value\" } }" -s >> /dev/null
    echo '"CHANGED_STRING" = "New value";' > "$translations_path/en.lproj/$file_name";
    echo '"CHANGED_STRING" = "Old-de-value";' > "$translations_path/de.lproj/$file_name";
    echo "\"CHANGED_STRING\" = \"$old_fr_value\";" > $fr_path;
    output=`$script $tenant_token -p ../$app_name`
    changed_translation=`grep 'CHANGED_STRING' $fr_path | cut -d '=' -f 2`
    assert_not_equals " \"$old_fr_value\";" "$changed_translation"
}

test_ignore_comments_for_developers() {
    path="$translations_path/en.lproj/$file_name";
    echo '//  MARK: common
/// str = developer comment
// just description
//FIXME: bad string
"dev_comments" = "comments for developers";' > $path
    output=`$script $tenant_token -p ../$app_name`
    description=`curl -H "Accept: application/json" -H "Authorization: Bearer $tenant_token" -L "$api_url/products/$product_id/strings/dev_comments" -s | jq -r '.description'`
    assert_equals 'just description' "$description"
}

test_retry_and_fail_to_get_translations() {
    local_env_init
    export API_URL=localhost:55555
    export TRANSLATION_RETRIES_NUMBER=3
    echo "$initial_data" > "$translations_path/en.lproj/$file_name"
    output=`$script $tenant_token -p ../$app_name`
    retries_number=`echo "$output" | grep -c 'Failed to get auto-translations. Retrying'`
    is_exit_with_error=`echo "$output" | grep -c "$translation_error_mark"`
    assert_equals $TRANSLATION_RETRIES_NUMBER $retries_number
    assert_equals 1 $is_exit_with_error
    export API_URL=$api_url
}

test_free_plan_exhausted() {
    local_env_init
    fake curl echo '{"paymentLinks": {"premium": "premium","unlimitedAi": "unlimitedAi"}}'
    output=`$script $tenant_token -p ../$app_name`
    is_exit_with_error=`echo "$output" | grep -c "$free_plan_exhausted_mark"`
    assert_equals 1 $is_exit_with_error
}

test_required_descr_for_non_manual_translations() {
    local_env_init
    add_manual_translation 'Cancel'
    output=`$script $tenant_token -p ../$app_name -d only-new`
    assert_equals 1 `echo "$output" | grep -c '"Saved successfully" has no description'`
}

test_required_descr_for_all_translations() {
    add_manual_translation 'Cancel'
    echo "$initial_data" > "$translations_path/en.lproj/$file_name"
    output=`$script $tenant_token -p ../$app_name -d required`
    assert_equals 1 `echo "$output" | grep -c '"Cancel" has no description'`
}

test_no_error_when_manual_translation_has_descr() {
    add_manual_translation 'Cancel' 'mobile app'
    echo '// mobile app' > "$translations_path/en.lproj/$file_name"
    echo "$initial_data" >> "$translations_path/en.lproj/$file_name"
    output=`$script $tenant_token -p ../$app_name -d required`
    assert_equals 0 `echo "$output" | grep -c '"Cancel" has no description'`
}

test_invalid_descr_requirement() {
    output=`$script $tenant_token -p ../$app_name -d INVALID`
    assert_equals 1 `echo "$output" | grep -c 'Invalid description requirement'`
}

test_load_all_auto_translations_if_files_empty() {
    echo "$initial_data" > "$translations_path/en.lproj/$file_name"
    output=`$script $tenant_token -p ../$app_name`
    echo "" > "$translations_path/fr.lproj/$file_name"
    echo "" > "$translations_path/de.lproj/$file_name"
    output=`$script $tenant_token -p ../$app_name`
    assert_equals 1 `echo "$output" | grep -c 'Indexing auto translations'`
    assert_equals 0 `echo "$output" | grep -c 'Getting auto-translations for'`
}
