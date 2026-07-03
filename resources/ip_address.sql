SET @db = 'fog';
SET @search = '192.168.0.110';

SELECT GROUP_CONCAT(
  CONCAT(
    'SELECT ''', table_name, ''' AS table_name, ',
    '''', column_name, ''' AS column_name, ',
    'CAST(`', column_name, '` AS CHAR) AS matched_value ',
    'FROM `', table_schema, '`.`', table_name, '` ',
    'WHERE `', column_name, '` LIKE ''%', REPLACE(@search, '''', ''''''), '%'''
  )
  SEPARATOR ' UNION ALL '
) INTO @sql
FROM information_schema.columns
WHERE table_schema = @db
  AND data_type IN ('char','varchar','tinytext','text','mediumtext','longtext','enum','set');

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
