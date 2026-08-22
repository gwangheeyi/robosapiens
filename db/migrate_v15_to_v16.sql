-- RoboSapiens schema v15 -> v16: drive failure diagnosis
USE `robosapiens`;

ALTER TABLE `drive_learning_samples`
  ADD COLUMN `nav2_status` INT NULL AFTER `success`,
  ADD COLUMN `failure_reason` TEXT NULL AFTER `nav2_status`,
  ADD COLUMN `error_log` MEDIUMTEXT NULL AFTER `failure_reason`;

UPDATE `schema_version`
SET `version` = 16, `applied_at` = NOW(6)
WHERE `id` = 1 AND `version` = 15;
