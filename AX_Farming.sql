-- ============================================================
--  AX_Farming | ax_farming.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS `ax_farming_plants` (
    `id`            INT UNSIGNED     NOT NULL AUTO_INCREMENT,
    `owner`         VARCHAR(60)      NOT NULL,
    `plant_type`    VARCHAR(50)      NOT NULL,
    `x`             FLOAT            NOT NULL,
    `y`             FLOAT            NOT NULL,
    `z`             FLOAT            NOT NULL,
    `growth`        TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `water`         TINYINT UNSIGNED NOT NULL DEFAULT 50,
    `fertilizer`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `health`        TINYINT UNSIGNED NOT NULL DEFAULT 100,
    `state`         ENUM('growing','ready','wilting','rotten','dead') NOT NULL DEFAULT 'growing',
    `rot_timer`     INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Segundos desde que llego al 100%',
    `grow_timer`    INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Segundos desde que fue plantada',
    `planted_at`    DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_owner` (`owner`),
    INDEX `idx_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Si ya tienes la tabla creada, ejecuta esto para agregar la columna:
-- ALTER TABLE `ax_farming_plants` ADD COLUMN `grow_timer` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `rot_timer`;
-- ALTER TABLE `ax_farming_plants` MODIFY COLUMN `rot_timer` INT UNSIGNED NOT NULL DEFAULT 0;