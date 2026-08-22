-- RoboSapiens schema v14 -> v15: waypoint drive learning
USE `robosapiens`;

CREATE TABLE IF NOT EXISTS `drive_learning_samples` (
  `id`                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `map_name`             VARCHAR(255) NOT NULL,
  `task_id`              VARCHAR(64)  NOT NULL,
  `task_name`            VARCHAR(255) NOT NULL,
  `robot_id`             VARCHAR(64)  NOT NULL,
  `waypoint_name`        VARCHAR(255) NOT NULL,
  `drive_mode`           VARCHAR(16)  NOT NULL,
  `started_at`           DATETIME(6)  NOT NULL,
  `finished_at`          DATETIME(6)  NOT NULL,
  `linear_velocity`      DOUBLE NOT NULL,
  `linear_acceleration`  DOUBLE NOT NULL,
  `angular_velocity`     DOUBLE NOT NULL,
  `angular_acceleration` DOUBLE NOT NULL,
  `goal_tolerance`       DOUBLE NOT NULL,
  `goal_x`               DOUBLE NOT NULL,
  `goal_y`               DOUBLE NOT NULL,
  `actual_x`             DOUBLE NOT NULL,
  `actual_y`             DOUBLE NOT NULL,
  `position_error`       DOUBLE NOT NULL,
  `goal_heading`         DOUBLE NULL,
  `actual_heading`       DOUBLE NULL,
  `heading_error`        DOUBLE NULL,
  `success`              TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_drive_learning_map_waypoint` (`map_name`, `waypoint_name`),
  KEY `idx_drive_learning_robot_finished` (`robot_id`, `finished_at`),
  CONSTRAINT `chk_drive_learning_mode` CHECK (`drive_mode` IN ('normal', 'forced'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE `schema_version`
SET `version` = 15, `applied_at` = NOW(6)
WHERE `id` = 1 AND `version` = 14;
