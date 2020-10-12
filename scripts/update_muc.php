<?php
    // Map input parameters.
    $redisHostName = $argv[1];
    $redisName = $argv[2];
    $redisPassword = $argv[3];
    $configFilePath = $argv[4];

    // Allow and load MUC config file.
    defined('MOODLE_INTERNAL') or define('MOODLE_INTERNAL', 'SomeDefaultValue');
    require($configFilePath);

    // Add Redis Cache Store instance.
    $configuration['stores'][$redisName] =
        array (
        'name' => $redisName,
        'plugin' => 'redis',
        'configuration' =>
        array (
        'server' => $redisHostName,
        'prefix' => 'mdl_',
        'password' => $redisPassword,
        'serializer' => '1',
        'compressor' => '0',
        ),
        'features' => 26,
        'modes' => 3,
        'mappingsonly' => false,
        'class' => 'cachestore_redis',
        'default' => false,
        'lock' => 'cachelock_file_default',
        );

    // Set default Cache Store to Redis for Application and Session modes.
    $configuration['modemappings'][0]['store'] = $redisName;
    $configuration['modemappings'][0]['sort'] = 0;
    $configuration['modemappings'][1]['store'] = $redisName;
    $configuration['modemappings'][1]['sort'] = 0;
    $configuration['modemappings'][2]['sort'] = 0;

    // Replace config file content with updated configuration.
    $output = "<?php defined('MOODLE_INTERNAL') || die();" . PHP_EOL;
    $output .= " \$configuration = " . var_export($configuration, true) . ";";
    file_put_contents($configFilePath, $output);
