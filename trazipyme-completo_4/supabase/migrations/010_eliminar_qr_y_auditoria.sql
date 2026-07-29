-- =========================================================
-- Eliminación de QR (soft-delete) + auditoría completa del ciclo de vida
-- del producto (creación/edición/eliminación) en el mismo historial que
-- ya usan los movimientos de stock.
-- =========================================================

-- Nuevos tipos de evento: además de ENTRADA/SALIDA/MUESTRA, el historial
-- ahora también registra el ciclo de vida del propio producto.
alter type movimiento_tipo add value if not exists 'CREACION';
alter type movimiento_tipo add value if not exists 'EDICION';
alter type movimiento_tipo add value if not exists 'ELIMINACION';
