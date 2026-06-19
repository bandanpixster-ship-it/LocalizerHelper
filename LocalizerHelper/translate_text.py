import sys
import argparse
import subprocess

def install_and_import():
    try:
        from deep_translator import GoogleTranslator
        return GoogleTranslator
    except ImportError:
        # Dependency should be bundled with the app; try to load from the bundle.
        import os
        bundle_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "deep_translator"))
        if os.path.isdir(bundle_dir):
            sys.path.insert(0, bundle_dir)
        try:
            from deep_translator import GoogleTranslator
            return GoogleTranslator
        except Exception as e:
            print(f"Missing bundled deep_translator package: {e}", file=sys.stderr)
            sys.exit(1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--text', required=True, help="Text to translate")
    parser.add_argument('--target', required=True, help="Target language code")
    parser.add_argument('--source', default="en", help="Source language code")
    args = parser.parse_args()

    GoogleTranslator = install_and_import()

    # Map locale names if needed
    target_lang = args.target.replace("_", "-")
    # Simple normalizations
    if target_lang.lower() == "zh-hans":
        target_lang = "zh-CN"
    elif target_lang.lower() == "zh-hant":
        target_lang = "zh-TW"

    try:
        translator = GoogleTranslator(source=args.source, target=target_lang.lower())
        result = translator.translate(args.text)
        print(result)
    except Exception as e:
        print(f"Translation error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
