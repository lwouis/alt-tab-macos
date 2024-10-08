# -*- coding: utf-8 -*-

import os
import argparse
from googletrans import Translator
import time

comment = "/* No comment provided by engineer. */"


def get_language_code(directory_name):
    """
    Convert the language folder name in the i18n directory to Google Translate language code.
    """
    lang_map = {
        'zh-Hans': 'zh-cn',
        'zh-CN': 'zh-cn',
        'zh-Hant': 'zh-tw',
        'zh-TW': 'zh-tw',
        'zh-HK': 'zh-tw',
    }
    return lang_map.get(directory_name, directory_name)


def read_localizable_strings_with_comments(file_path):
    """
    Read the Localizable.strings file into a dictionary, including comments.
    """
    translations = {}
    comments = {}
    current_comment = []
    if os.path.isfile(file_path):
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line.startswith('/*') and line.endswith('*/'):
                    current_comment.append(line)
                elif line.startswith('/*'):
                    current_comment.append(line)
                elif line.endswith('*/'):
                    current_comment.append(line)
                elif line == "":
                    if current_comment:
                        current_comment.append(line)
                elif '=' in line:
                    key, value = line.split('=', 1)
                    translations[key.strip()] = value.strip().strip(';').strip('"')
                    if current_comment:
                        comments[key.strip()] = "\n".join(current_comment)
                        current_comment = []
    return translations, comments


def translate_text(translator, text, src_lang, dest_lang, max_retries=0):
    """
    Translate text with retries in case of failure.
    """
    for attempt in range(max_retries):
        try:
            translated = translator.translate(text, src=src_lang, dest=dest_lang).text
            return translated
        except Exception as e:
            print(f"Failed to translate '{text}' to '{dest_lang}' on attempt {attempt + 1}: {e}")
            time.sleep(1)  # Wait before retrying
    print(f"Failed to translate '{text}' to '{dest_lang}' after {max_retries} attempts, fallback to English.")
    return text  # Fallback to original text if all retries fail


def translate_lines(original_translations, original_comments, language_dirs, original_language, replace_mode, i18n_dir,
                    failed_translations, retry_translate):
    # Initialize the translator
    translator = Translator()
    total_lines = len(original_translations)
    total_dirs = len(language_dirs)

    for dir_idx, lang_dir in enumerate(language_dirs, start=1):
        print(f'Translating directory {dir_idx}/{total_dirs}: {lang_dir}')

        # Determine the target file path and language code
        if lang_dir == f'{original_language}.lproj' or (original_language is None and lang_dir == 'en.lproj'):
            target_file = os.path.join(i18n_dir, 'en.lproj', 'Localizable.strings')
            google_code = 'en'
        else:
            lang_code = lang_dir.split('.')[0]
            google_code = get_language_code(lang_code)
            target_file = os.path.join(i18n_dir, lang_dir, 'Localizable.strings')

        os.makedirs(os.path.dirname(target_file), exist_ok=True)

        # Read the existing translations in the target language file
        target_translations, target_comments = read_localizable_strings_with_comments(target_file)

        # Open the target language file for writing
        with open(target_file, 'w', encoding='utf-8') as f:
            for idx, (key, original_value) in enumerate(original_translations.items(), start=1):
                translated_value = target_translations.get(key)
                original_comment = original_comments.get(key, comment)

                # Check if the translation exists and contains no placeholders, or if replace mode is enabled
                if translated_value and '{' not in translated_value and '}' not in translated_value and not replace_mode:
                    if retry_translate and translated_value == original_value:
                        translated = translate_text(translator, original_value, 'en', google_code)
                        # Print progress in one line
                        print(
                            f'Retrying translation for {google_code} ({idx}/{total_lines}): Original: {original_value}, Translated: {translated}')
                        # Write the translated content with default comment if none provided
                        f.write(f'{original_comment}\n{key} = "{translated}";\n\n')
                    else:
                        target_comment = target_comments.get(key, original_comment)
                        f.write(f'{target_comment}\n{key} = "{translated_value}";\n\n')
                else:
                    translated = translate_text(translator, original_value, 'en', google_code)
                    # Print progress in one line
                    print(
                        f'Translating for {google_code} ({idx}/{total_lines}): Original: {original_value}, Translated: {translated}')
                    # Write the translated content with default comment if none provided
                    f.write(f'{original_comment}\n{key} = "{translated}";\n\n')


def translate_specific_content(specific_content, language_dirs, original_language, i18n_dir, failed_translations):
    # Initialize the translator
    translator = Translator()
    total_dirs = len(language_dirs)
    for dir_idx, lang_dir in enumerate(language_dirs, start=1):
        print(f'Translating directory {dir_idx}/{total_dirs}: {lang_dir}')
        if lang_dir == f'{original_language}.lproj' or lang_dir == 'en.lproj':
            continue  # Skip the original language

        # Parse the language code
        lang_code = lang_dir.split('.')[0]
        google_code = get_language_code(lang_code)

        # Generate the target language file path
        target_file = os.path.join(i18n_dir, lang_dir, 'Localizable.strings')
        os.makedirs(os.path.dirname(target_file), exist_ok=True)

        translated = translate_text(translator, specific_content, 'en', google_code)
        # Print progress in one line
        print(
            f'Translating for {google_code} ({dir_idx}/{total_dirs}): Original: {specific_content}, Translated: {translated}')

        # Append the translated content to the end of the file with default comment if none provided
        with open(target_file, 'a', encoding='utf-8') as f:
            f.write(f'{comment}\n"{specific_content}" = "{translated}";\n\n')


def translate_files(i18n_dir, original_language=None, specific_content=None, replace_mode=False, retry_translate=False):
    # Get all language subdirectories and sort them alphabetically
    language_dirs = sorted([d for d in os.listdir(i18n_dir) if os.path.isdir(os.path.join(i18n_dir, d))])
    failed_translations = []

    # Determine the path of the original language file
    if original_language:
        original_file_path = os.path.join(i18n_dir, f'{original_language}.lproj', 'Localizable.strings')
    else:
        original_file_path = os.path.join(i18n_dir, 'Localizable.strings')

    if not os.path.isfile(original_file_path):
        print(f"Error: The original language file {original_file_path} does not exist.")
        return

    if specific_content is None:
        # Read the original language file into a dictionary
        original_translations, original_comments = read_localizable_strings_with_comments(original_file_path)
        translate_lines(original_translations, original_comments, language_dirs, original_language, replace_mode,
                        i18n_dir, failed_translations, retry_translate)
    else:
        translate_specific_content(specific_content, language_dirs, original_language, i18n_dir, failed_translations)

    print('Translation completed!')

    if failed_translations:
        print('The following languages failed to translate:')
        for lang in set(failed_translations):
            print(lang)


def main():
    usage = """
    Usage:
    python translate_i18n_tools.py <i18n_dir> [--original_language <language_code>] [--specific_content <content>] [--replace] [--retry_translate]

    Arguments:
    <i18n_dir>                  Required. Path to the i18n directory.
    --original_language         Optional. Original language code. If not provided, the script will use the Localizable.strings file in the root of i18n_dir.
    --specific_content          Optional. Specific content to be translated and appended.
    --replace                   Optional. If specified, force replace existing translations.
    --retry_translate           Optional. If specified, retry translation for target language if translated value is in English.

    Examples:
    python translate_i18n_tools.py path_to_your_i18n_directory
    python translate_i18n_tools.py path_to_your_i18n_directory --original_language en
    python translate_i18n_tools.py path_to_your_i18n_directory --specific_content "This is a specific content to be translated."
    python translate_i18n_tools.py path_to_your_i18n_directory --original_language en --replace
    python translate_i18n_tools.py path_to_your_i18n_directory --original_language en --retry_translate
    """

    parser = argparse.ArgumentParser(description='Translate i18n files or specific content.', usage=usage)
    parser.add_argument('i18n_dir', type=str, help='Path to the i18n directory')
    parser.add_argument('--original_language', type=str, help='Original language code')
    parser.add_argument('--specific_content', type=str, help='Specific content to be translated and appended')
    parser.add_argument('--replace', action='store_true', help='Force replace existing translations')
    parser.add_argument('--retry_translate', action='store_true',
                        help='Retry translation for target language if translated value is in English')

    args = parser.parse_args()

    if not os.path.isdir(args.i18n_dir):
        print(f"Error: The directory {args.i18n_dir} does not exist.")
        parser.print_help()
        return

    translate_files(args.i18n_dir, args.original_language, args.specific_content, args.replace, args.retry_translate)


if __name__ == '__main__':
    main()
    # translate_files(i18n_dir="/Users/allsochen/AppCodeProjects/alt-tab-macos/resources/l10n",
    #                 replace_mode=False, retry_translate=False)
