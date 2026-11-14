CREATE TABLE IF NOT EXISTS `ems_patients` (
    `citizenid` VARCHAR(50) NOT NULL,
    `conditions` LONGTEXT NOT NULL DEFAULT '[]',
    `emergency_contact` VARCHAR(120) NOT NULL DEFAULT '',
    `notes` TEXT NOT NULL DEFAULT '',
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    CONSTRAINT `fk_ems_patients_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_reports` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) DEFAULT NULL,
    `patient_name` VARCHAR(120) NOT NULL DEFAULT '',
    `call_id` INT UNSIGNED DEFAULT NULL,
    `medic_citizenid` VARCHAR(50) DEFAULT NULL,
    `medic_name` VARCHAR(120) NOT NULL DEFAULT '',
    `injuries` LONGTEXT NOT NULL DEFAULT '[]',
    `medications` LONGTEXT NOT NULL DEFAULT '[]',
    `extras` LONGTEXT NOT NULL DEFAULT '[]',
    `narrative` TEXT NOT NULL DEFAULT '',
    `summary` VARCHAR(255) NOT NULL DEFAULT '',
    `outcome` ENUM('scene', 'transported', 'deceased', 'respawned') NOT NULL DEFAULT 'scene',
    `status` ENUM('draft', 'filed') NOT NULL DEFAULT 'draft',
    `billing` ENUM('pending', 'billed', 'waived') NOT NULL DEFAULT 'pending',
    `billed` INT UNSIGNED DEFAULT NULL,
    `shared_with_police` TINYINT(1) NOT NULL DEFAULT 0,
    `occurred_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ems_reports_citizen` (`citizenid`),
    KEY `idx_ems_reports_medic` (`medic_citizenid`),
    CONSTRAINT `fk_ems_reports_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_prescriptions` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `medication` VARCHAR(120) NOT NULL,
    `dose` VARCHAR(160) NOT NULL DEFAULT '',
    `reason` VARCHAR(160) NOT NULL DEFAULT '',
    `refills` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `fills` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `last_pharmacy` VARCHAR(120) DEFAULT NULL,
    `last_filled_at` TIMESTAMP NULL DEFAULT NULL,
    `controlled` TINYINT(1) NOT NULL DEFAULT 0,
    `prescriber_citizenid` VARCHAR(50) DEFAULT NULL,
    `prescriber_name` VARCHAR(120) NOT NULL DEFAULT '',
    `status` ENUM('active', 'cancelled') NOT NULL DEFAULT 'active',
    `ends_at` TIMESTAMP NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ems_prescriptions_citizen` (`citizenid`, `id`),
    CONSTRAINT `fk_ems_prescriptions_player` FOREIGN KEY (`citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_revives` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `medic_citizenid` VARCHAR(50) NOT NULL,
    `patient_citizenid` VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_ems_revives_medic` (`medic_citizenid`, `created_at`),
    CONSTRAINT `fk_ems_revives_medic` FOREIGN KEY (`medic_citizenid`) REFERENCES `players` (`citizenid`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_ranks` (
    `grade` TINYINT UNSIGNED NOT NULL,
    `permissions` LONGTEXT NOT NULL DEFAULT '{}',
    PRIMARY KEY (`grade`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_treatments` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `category` ENUM('injury', 'procedure', 'medication', 'fee') NOT NULL DEFAULT 'injury',
    `treats` LONGTEXT NOT NULL DEFAULT '[]',
    `item` VARCHAR(64) DEFAULT NULL,
    `price` INT UNSIGNED NOT NULL DEFAULT 0,
    `seconds` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_templates` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `narrative` TEXT NOT NULL DEFAULT '',
    `uses` INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ems_settings` (
    `id` TINYINT UNSIGNED NOT NULL,
    `data` LONGTEXT NOT NULL DEFAULT '{}',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
