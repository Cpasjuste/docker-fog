SET @db = 'fog';
SET @search = '0.0.0.0';
SET SESSION group_concat_max_len = 1000000;

SELECT GROUP_CONCAT(sql_text SEPARATOR ' UNION ALL ')
INTO @sql
FROM (
  SELECT CONCAT(
    'SELECT ',
    QUOTE(c.table_name), ' AS table_name, ',
    QUOTE(c.column_name), ' AS column_name, ',
    COALESCE(CONCAT(QUOTE(pk.pk_columns), ' AS pk_columns, '), 'NULL AS pk_columns, '),
    'CAST(`', c.column_name, '` AS CHAR) AS matched_value, ',
    'CONCAT(',
      QUOTE(CONCAT('SELECT * FROM `', c.table_schema, '`.`', c.table_name, '` WHERE `', c.column_name, '` = ')),
      ', QUOTE(CAST(`', c.column_name, '` AS CHAR)), ',
      QUOTE(';'),
    ') AS inspect_sql ',
    'FROM `', c.table_schema, '`.`', c.table_name, '` ',
    'WHERE CAST(`', c.column_name, '` AS CHAR) LIKE ',
    QUOTE(CONCAT('%', @search, '%'))
  ) AS sql_text
  FROM information_schema.columns c
  LEFT JOIN (
    SELECT table_schema, table_name,
           GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ', ') AS pk_columns
    FROM information_schema.statistics
    WHERE index_name = 'PRIMARY'
    GROUP BY table_schema, table_name
  ) pk
    ON pk.table_schema = c.table_schema
   AND pk.table_name = c.table_name
  WHERE c.table_schema = @db
    AND c.data_type IN ('char','varchar','tinytext','text','mediumtext','longtext','enum','set')
) s;

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;