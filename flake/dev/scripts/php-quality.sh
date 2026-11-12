# shellcheck shell=bash
# The builder supplies the output path.
# shellcheck disable=SC2154
cd @source@ || exit
while IFS= read -r -d '' source; do
  php -n -l "$source"
done < <(find . -type f -name '*.php' -print0)
php-cs-fixer fix --config .php-cs-fixer.dist.php --dry-run --diff --using-cache=no
touch "$out"
