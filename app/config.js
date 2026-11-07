// =====================================================================
//  CONEXIÓN A POSTGRESQL
//  Los datos se leen del archivo .env (copie .env.example a .env).
//  NUNCA suba el archivo .env a GitHub: contiene la contraseña.
// =====================================================================
require('dotenv').config();

const ssl = (process.env.DB_SSL || 'false').toLowerCase() === 'true';

module.exports = {
  // Opción 1: una sola cadena de conexión (la que entrega Supabase)
  connectionString: process.env.DATABASE_URL || null,
  // Opción 2: datos por separado (PostgreSQL local con pgAdmin)
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'postobon',
  schema: process.env.DB_SCHEMA || 'inventario_postobon',
  ssl: ssl ? { rejectUnauthorized: false } : false,
  puertoWeb: parseInt(process.env.PORT || '3000', 10)
};
