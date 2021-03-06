﻿SET role oiv_admin;
SET search_path = algemeen, pg_catalog, public;

CREATE TABLE gt_pk_metadata_table
(
  table_schema  CHARACTER VARYING(32) NOT NULL,
  table_name    CHARACTER VARYING(32) NOT NULL,
  pk_column     CHARACTER VARYING(32) NOT NULL,
  pk_column_idx INTEGER,
  pk_policy     CHARACTER VARYING(32),
  pk_sequence   CHARACTER VARYING(64),
  CONSTRAINT gt_pk_metadata_table_table_schema_table_name_pk_column_key UNIQUE (table_schema, table_name, pk_column),
  CONSTRAINT gt_pk_metadata_table_pk_policy_check CHECK (pk_policy :: TEXT = ANY
                                                         (ARRAY ['sequence' :: CHARACTER VARYING, 'assigned' :: CHARACTER VARYING, 'autogenerated' :: CHARACTER VARYING] :: TEXT []))
);

INSERT INTO gt_pk_metadata_table VALUES ('algemeen', 'fotografie_cogo', 'id', NULL, 'sequence', 'algemeen.fotografie_id_seq');
--INSERT INTO gt_pk_metadata_table VALUES ('algemeen', 'fotografie_cogo', 'id', 1, 'assigned');

CREATE TABLE fotografie
(
  id             SERIAL PRIMARY KEY NOT NULL,
  geom           GEOMETRY(POINT, 28992) NOT NULL,
  datum_aangemaakt TIMESTAMP WITH TIME ZONE DEFAULT now(),
  datum_gewijzigd   TIMESTAMP WITH TIME ZONE,
  uitgesloten BOOLEAN DEFAULT FALSE,
  src           TEXT NOT NULL,
  exif           JSON,
  datum          VARCHAR(255),
  rd_x           NUMERIC,
  rd_y           NUMERIC,
  bestand           VARCHAR(255),
  fotograaf      VARCHAR(255),
  omschrijving   TEXT,
  bijzonderheden TEXT
);
CREATE INDEX sidx_fotografie_geom
  ON algemeen.fotografie
  USING gist
  (geom);
COMMENT ON TABLE fotografie IS 'Algemene fotografie tabel';

CREATE OR REPLACE VIEW algemeen.fotografie_cogo AS 
 SELECT id,
    geom,
    src,
    exif::TEXT,
    datum as datetime,
    bestand as filename,
    fotograaf,
    omschrijving,
    bijzonderheden
   FROM fotografie
   WHERE uitgesloten != TRUE;

CREATE OR REPLACE RULE fotografie_cogo_del AS
ON DELETE TO fotografie_cogo DO INSTEAD
UPDATE fotografie set uitgesloten = TRUE WHERE old.id = id
RETURNING 
    id,
    geom,
    src,
    exif::TEXT,
    datum,
    bestand,
    fotograaf,
    omschrijving,
    bijzonderheden;

CREATE OR REPLACE RULE fotografie_cogo_ins AS
ON INSERT TO fotografie_cogo DO INSTEAD
  INSERT INTO fotografie (
    geom,
    src,
    exif,
    datum,
    rd_x,
    rd_y,
    bestand,
    fotograaf,
    omschrijving,
    bijzonderheden
  )
  VALUES (
    new.geom,
    new.src,
   new.exif::JSON,
    new.datetime,
    ST_X(new.geom),
    ST_Y(new.geom),
    new.filename,
    new.fotograaf,
    new.omschrijving,
    new.bijzonderheden)
RETURNING 
    id,
    geom,
    src,
    exif::TEXT,
    datum,
    bestand,
    fotograaf,
    omschrijving,
    bijzonderheden;

CREATE OR REPLACE RULE fotografie_cogo_upd AS
ON UPDATE TO fotografie_cogo DO INSTEAD
UPDATE fotografie set 
datum_gewijzigd = now(),
geom =    new.geom,
src =    new.src,
exif =    new.exif::JSON,
datum  =  new.datetime,
rd_x  =  ST_X(new.geom),
rd_y =    ST_Y(new.geom),
bestand =    new.filename,
fotograaf =    new.fotograaf,
omschrijving =    new.omschrijving,
bijzonderheden =    new.bijzonderheden
WHERE new.id = id
RETURNING 
    id,
    geom,
    src,
    exif::TEXT,
    datum,
    bestand,
    fotograaf,
    omschrijving,
    bijzonderheden;

-- Update versie van de applicatie
UPDATE algemeen.applicatie SET sub = 6;
UPDATE algemeen.applicatie SET revisie = 1;
UPDATE algemeen.applicatie SET db_versie = 261; -- db versie == versie_sub_revisie
UPDATE algemeen.applicatie SET datum = now();