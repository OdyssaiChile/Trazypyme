-- Traspaso de stock entre bodegas de la misma empresa.
-- Se registra como dos movimientos ligados (salida en origen, entrada en
-- destino) para que el historial de cada bodega cuadre por separado.
alter type movimiento_tipo add value if not exists 'TRASPASO_SALIDA';
alter type movimiento_tipo add value if not exists 'TRASPASO_ENTRADA';
