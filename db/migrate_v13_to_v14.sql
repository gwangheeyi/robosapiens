-- RoboSapiens schema v13 -> v14: product master
USE `robosapiens`;

CREATE TABLE IF NOT EXISTS `products` (
  `id`           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sku`          VARCHAR(64)     NOT NULL,
  `name`         VARCHAR(160)    NOT NULL,
  `category`     VARCHAR(80)     NOT NULL DEFAULT '',
  -- Robot scheduling code: ambient | chilled | frozen
  `storage_type` VARCHAR(16)     NOT NULL,
  `unit`         VARCHAR(24)     NOT NULL DEFAULT '개',
  `price`        DECIMAL(12,2)   NOT NULL DEFAULT 0,
  `stock_qty`    INT             NOT NULL DEFAULT 0,
  `safety_stock` INT             NOT NULL DEFAULT 0,
  `active`       TINYINT(1)      NOT NULL DEFAULT 1,
  `notes`        VARCHAR(500)    NOT NULL DEFAULT '',
  `created_at`   DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at`   DATETIME(6)     NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
                                  ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_products_sku` (`sku`),
  KEY `idx_products_storage_active` (`storage_type`, `active`),
  KEY `idx_products_name` (`name`),
  CONSTRAINT `chk_products_storage_type`
    CHECK (`storage_type` IN ('ambient', 'chilled', 'frozen')),
  CONSTRAINT `chk_products_price` CHECK (`price` >= 0),
  CONSTRAINT `chk_products_stock` CHECK (`stock_qty` >= 0),
  CONSTRAINT `chk_products_safety_stock` CHECK (`safety_stock` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE `schema_version`
SET `version` = 14, `applied_at` = NOW(6)
WHERE `id` = 1 AND `version` = 13;
