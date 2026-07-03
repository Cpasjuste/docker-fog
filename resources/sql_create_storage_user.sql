CREATE USER IF NOT EXISTS 'fogstorage'@'%' IDENTIFIED BY 'fogstorage';

GRANT ALL PRIVILEGES
ON fog.*
TO 'fogstorage'@'%';

FLUSH PRIVILEGES;

