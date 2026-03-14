-- ═══════════════════════════════════════════════════════════
--  prop_placement – SQL Installation
--  Einmalig ausführen bevor der Server gestartet wird!
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS `prop_placement_props` (
    `id`                INT(11)         NOT NULL AUTO_INCREMENT,
    `item_name`         VARCHAR(64)     NOT NULL COMMENT 'ox_inventory Item-Name',
    `model`             VARCHAR(128)    NOT NULL COMMENT 'GTA5 Prop-Modell-Name',
    `x`                 FLOAT           NOT NULL,
    `y`                 FLOAT           NOT NULL,
    `z`                 FLOAT           NOT NULL,
    `rotation`          FLOAT           NOT NULL DEFAULT 0.0 COMMENT 'Z-Rotation in Grad',
    `owner_identifier`  VARCHAR(128)    DEFAULT NULL COMMENT 'License-Identifier des Besitzers',
    `owner_job`         VARCHAR(64)     DEFAULT NULL COMMENT 'Job des Besitzers zum Platzierdpunkt',
    `persistent`        TINYINT(1)      NOT NULL DEFAULT 1 COMMENT '1 = überlebt Neustart',
    `placed_at`         TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_owner` (`owner_identifier`),
    INDEX `idx_persistent` (`persistent`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='prop_placement – Persistent placed props';

CREATE TABLE IF NOT EXISTS `prop_placement_logs` (
    `id`            INT(11)         NOT NULL AUTO_INCREMENT,
    `action`        ENUM('place','remove','admin_give','admin_clear') NOT NULL,
    `server_id`     INT(11)         DEFAULT NULL COMMENT 'FiveM Server-ID (0 = Konsole)',
    `identifier`    VARCHAR(128)    DEFAULT NULL COMMENT 'License-Identifier',
    `player_name`   VARCHAR(128)    DEFAULT NULL,
    `prop_id`       INT(11)         DEFAULT NULL COMMENT 'ID aus prop_placement_props',
    `item_name`     VARCHAR(64)     DEFAULT NULL,
    `model`         VARCHAR(128)    DEFAULT NULL,
    `coords`        JSON            DEFAULT NULL COMMENT '{x,y,z,rotation}',
    `extra`         JSON            DEFAULT NULL COMMENT 'Zusätzliche Kontextdaten',
    `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_action`     (`action`),
    INDEX `idx_identifier` (`identifier`),
    INDEX `idx_item`       (`item_name`),
    INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='prop_placement – Audit-Log aller Aktionen';

-- ═══════════════════════════════════════════════════════════
--  ox_inventory Items hinzufügen
--  Diese Zeilen in: ox_inventory/data/items.lua einfügen!
-- ═══════════════════════════════════════════════════════════

--[[
    -- In ox_inventory/data/items.lua hinzufügen:

    ['wooden_crate'] = {
        label  = 'Holzkiste',
        weight = 2000,
        stack  = true,
        close  = true,
    },
    ['metal_crate'] = {
        label  = 'Metallkiste',
        weight = 3000,
        stack  = true,
        close  = true,
    },
    ['plastic_bin'] = {
        label  = 'Mülleimer',
        weight = 800,
        stack  = true,
        close  = true,
    },
    ['garden_chair'] = {
        label  = 'Gartenstuhl',
        weight = 1500,
        stack  = true,
        close  = true,
    },
    ['folding_table'] = {
        label  = 'Klapptisch',
        weight = 2500,
        stack  = true,
        close  = true,
    },
    ['traffic_cone'] = {
        label  = 'Verkehrskegel',
        weight = 500,
        stack  = true,
        close  = true,
    },
    ['police_barrier'] = {
        label  = 'Polizeiabsperrung',
        weight = 3000,
        stack  = true,
        close  = true,
    },
    ['road_barrier'] = {
        label  = 'Straßensperre',
        weight = 5000,
        stack  = true,
        close  = true,
    },
    ['spike_strip'] = {
        label  = 'Nagelstreifen',
        weight = 1000,
        stack  = true,
        close  = true,
    },
    ['worklight'] = {
        label  = 'Baustellenlampe',
        weight = 2000,
        stack  = true,
        close  = true,
    },
    ['generator'] = {
        label  = 'Generator',
        weight = 8000,
        stack  = false,
        close  = true,
    },
    ['scaffolding'] = {
        label  = 'Baugerüst',
        weight = 10000,
        stack  = false,
        close  = true,
    },
    ['admin_barrier_large'] = {
        label  = 'Große Absperrung (Admin)',
        weight = 1,
        stack  = true,
        close  = true,
    },
    ['admin_tent'] = {
        label  = 'Zelt (Admin)',
        weight = 1,
        stack  = true,
        close  = true,
    },
]]
