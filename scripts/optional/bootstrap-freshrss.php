<?php

declare(strict_types=1);

// Run as the FreshRSS service user after freshrss-config.service.
require getenv('FRESHRSS_PACKAGE') . '/cli/_cli.php';

$arguments = $argv ?? [];
if (count($arguments) !== 4) {
    throw new InvalidArgumentException('Supply the username, feed list, and marker paths.');
}
[$script, $username, $feedFile, $marker] = $arguments;
if ($username === '--username-credential') {
    $credentials = getenv('CREDENTIALS_DIRECTORY');
    if ($credentials === false || $credentials === '') {
        throw new RuntimeException('Missing FreshRSS credential directory');
    }
    $usernameContents = file_get_contents($credentials . '/news-username');
    if ($usernameContents === false) {
        throw new RuntimeException('Could not read the FreshRSS runtime username');
    }
    $username = rtrim($usernameContents, "\n");
    if (!preg_match('/^[A-Za-z0-9_][A-Za-z0-9_.@-]{1,38}$/D', $username)) {
        fail('Invalid FreshRSS runtime username');
    }
}
cliInitUser($username);
$feedContents = file_get_contents($feedFile);
if ($feedContents === false) {
    throw new RuntimeException('Could not read the FreshRSS starter feed list');
}
$feeds = json_decode($feedContents, true, 512, JSON_THROW_ON_ERROR);
if (!is_array($feeds)) {
    fail('Starter feed list is invalid');
}
$experienceMarker = $marker . '.experience-v3';
if (!is_file($experienceMarker)) {

    $extension = Minz_ExtensionManager::findExtension('Grid View');
    $requireGrid = getenv('FRESHRSS_REQUIRE_GRID') === '1';
    if ($requireGrid && $extension === null) {
        fail('The selected FreshRSS package lacks Grid View');
    }
    $settings = FreshRSS_Context::userConf();
    if ($extension !== null) {
        if ($extension->getType() !== 'user' || $extension->install() !== true) {
            fail('Could not install the FreshRSS Grid View extension');
        }
        $enabled = $settings->extensions_enabled;
        $enabled['Grid View'] = true;
        $settings->extensions_enabled = $enabled;
    }
    $settings->lazyload = true;
    $settings->default_view = 'all';
    $settings->sort = 'date';
    $settings->sort_order = 'DESC';
    $settings->retrieve_extension_list = false;
    $settings->theme = 'Origine';
    $settings->darkMode = 'auto';
    $settings->timezone = getenv('FRESHRSS_TIMEZONE') ?: 'UTC';
    $settings->secondary_sort = 'id';
    $settings->secondary_sort_order = 'DESC';
    $settings->posts_per_page = 30;
    $settings->topline_thumbnail = 'large';
    $settings->topline_summary = true;
    $settings->topline_myLabels = true;
    $settings->topline_sharing = true;
    $settings->topline_display_authors = true;
    $settings->hide_read_feeds = false;
    $settings->content_width = 'medium';
    $settings->auto_load_more = true;
    if ($extension !== null) {
        $extensionSettings = $settings->extensions;
        $extensionSettings[$extension->getName()] = array_merge($extensionSettings[$extension->getName()] ?? [], [
            'columns' => 3, 'fetch_og_image' => false, 'sort_by_date' => true,
            'sort_applied' => true, 'mobile_menu_button' => true, 'sticky_nav' => true,
        ]);
        $settings->extensions = $extensionSettings;
    }
    $queries = $settings->queries;
    $existingNames = array_column($queries, 'name');
    foreach ([
        'Today' => 'pubdate:P1D/',
        'This week' => 'pubdate:P7D/',
        'Science and technology' => '(intitle:science OR intitle:technology OR intitle:research)',
        'Space' => '(intitle:space OR intitle:astronomy OR intitle:planet)',
    ] as $name => $search) {
        if (!in_array($name, $existingNames, true)) {
            $queries[] = (new FreshRSS_UserQuery([
                'name' => $name, 'get' => 'a', 'order' => 'DESC', 'state' => 2,
                'search' => $search, 'shareRss' => false, 'shareOpml' => false,
            ], FreshRSS_Context::categories(), FreshRSS_Context::labels()))->toArray();
        }
    }
    $settings->queries = $queries;
    if (!$settings->save()) {
        fail('Could not save FreshRSS reading preferences');
    }

    $tagDao = FreshRSS_Factory::createTagDao();
    foreach (['Read later', 'Verify', 'Deep dive'] as $label) {
        if ($tagDao->searchByName($label) === null && $tagDao->addTag(['name' => $label]) === false) {
            fail('Could not create a starter reading label');
        }
    }
    $feedDao = FreshRSS_Factory::createFeedDao();
    foreach ($feeds as $feed) {
        $existingFeed = $feedDao->searchByUrl($feed['url']);
        if ($existingFeed !== null && !empty($feed['title']) && $existingFeed->name() === $feed['url']) {
            if (!$feedDao->updateFeed($existingFeed->id(), ['name' => $feed['title']])) {
                fail('Could not update a starter feed display name');
            }
        }
    }
    if (file_put_contents($experienceMarker, "Reader experience v3 applied. Later preferences are user-owned.\n", LOCK_EX) === false) {
        fail('Could not write the reader experience marker');
    }
}
if (is_file($marker)) {
    exit(0);
}
$categories = [];
foreach ($feeds as $feed) {
    $categories[$feed['category']][] = $feed;
}
$escape = static fn (string $value): string => htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
$opml = '<?xml version="1.0" encoding="UTF-8"?><opml version="2.0"><head><title>Curated news starters</title></head><body>';
foreach ($categories as $category => $urls) {
    $opml .= '<outline text="' . $escape($category) . '" title="' . $escape($category) . '">';
    foreach ($urls as $feed) {
        $title = $feed['title'] ?? $feed['url'];
        $opml .= '<outline text="' . $escape($title) . '" title="' . $escape($title) . '" type="rss" xmlUrl="' . $escape($feed['url']) . '"/>';
    }
    $opml .= '</outline>';
}
$opml .= '</body></opml>';
$temporary = $marker . '.partial.' . getmypid() . '.opml';
if (file_put_contents($temporary, $opml, LOCK_EX) === false) {
    fail('Could not write temporary OPML');
}
try {
    $controller = new FreshRSS_importExport_Controller();
    if (!$controller->importFile($temporary, $temporary, $username)) {
        fail('FreshRSS rejected the starter OPML');
    }
    if (file_put_contents($marker, "Starter feeds imported. Later changes are user-owned.\n", LOCK_EX) === false) {
        fail('Could not write the starter import marker');
    }
} finally {
    @unlink($temporary);
}
