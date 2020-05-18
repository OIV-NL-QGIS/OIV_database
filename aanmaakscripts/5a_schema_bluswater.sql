﻿SET ROLE oiv_admin;

DROP SCHEMA IF EXISTS bluswater CASCADE;

CREATE SCHEMA bluswater;
COMMENT ON SCHEMA bluswater IS 'OIV bluswater';

GRANT USAGE ON SCHEMA bluswater TO GROUP oiv_read;

SET search_path = bluswater, pg_catalog, public;

CREATE TABLE bluswater.brandkranen
(
  nummer       VARCHAR PRIMARY KEY,
  geom         GEOMETRY(POINT, 28992),
  type         VARCHAR,
  diameter     SMALLINT,
  postcode     VARCHAR,
  straat       VARCHAR,
  huisnummer   VARCHAR,
  capaciteit   SMALLINT,
  plaats       VARCHAR,
  gemeentenaam VARCHAR
);

CREATE INDEX brandkranen_geom_gist
  ON bluswater.brandkranen
  USING GIST
  (geom);

CREATE TABLE bluswater.leidingen
(
  id        SERIAL NOT NULL PRIMARY KEY,
  geom      GEOMETRY(LINESTRING, 28992),
  materiaal VARCHAR,
  diameter  NUMERIC
);

CREATE INDEX leidingen_geom_gist
  ON bluswater.leidingen
  USING GIST
  (geom);
  
-- Create table kavels t.b.v. de brandkraan controles
CREATE TABLE bluswater.kavels
(
  kavel serial NOT NULL,
  geom geometry(MultiPolygon,28992),
  post character varying(50),
  CONSTRAINT kavels_pkey PRIMARY KEY (kavel)
);

CREATE INDEX kavels_geom_gist
  ON kavels
  USING GIST
  (geom);

-- Create View kavels intersect brandkranen
CREATE OR REPLACE VIEW bluswater.brandkraan_kavels AS 
 SELECT b.nummer,
    concat(lower(k.post::text), '@vrnhn.nl') AS inlognaam,
    k.kavel
   FROM bluswater.brandkranen b
     JOIN bluswater.kavels k ON st_intersects(b.geom, k.geom);

CREATE OR REPLACE VIEW bluswater.leiding_huidig AS
  SELECT *
  FROM bluswater.leidingen;

CREATE OR REPLACE VIEW bluswater.brandkraan_huidig AS
  SELECT *
  FROM bluswater.brandkranen;

CREATE TABLE bluswater.plusinformatie
(
  id                SERIAL  NOT NULL PRIMARY KEY,
  brandkraan_nummer VARCHAR NOT NULL,
  datum_aangemaakt  TIMESTAMP WITH TIME ZONE DEFAULT now(),
  datum_gewijzigd   TIMESTAMP WITH TIME ZONE,
  verwijderd        BOOLEAN                  DEFAULT FALSE,
  frequentie        SMALLINT                 DEFAULT 24,
  opmerking         TEXT,
  kavel 			SMALLINT NOT NULL,
  inlognaam 		text NOT NULL
);
CREATE UNIQUE INDEX plusinformatie_brandkraan_nummer_uindex
  ON bluswater.plusinformatie (brandkraan_nummer);
COMMENT ON COLUMN bluswater.plusinformatie.frequentie IS 'Inspectie frequentie in maanden';

CREATE OR REPLACE VIEW bluswater.brandkraan_huidig_plus AS
  SELECT
    brandkraan_huidig.*,
    COALESCE(plusinformatie.verwijderd, FALSE) verwijderd,
    COALESCE(plusinformatie.frequentie, 24)    frequentie,
    plusinformatie.opmerking,
	plusinformatie.inlognaam
  FROM bluswater.brandkraan_huidig
    LEFT JOIN plusinformatie ON brandkraan_huidig.nummer = brandkraan_nummer;

CREATE TABLE enum_conditie (
  value TEXT NOT NULL PRIMARY KEY
);

INSERT INTO enum_conditie (value) VALUES ('goedgekeurd');
INSERT INTO enum_conditie (value) VALUES ('afgekeurd');
INSERT INTO enum_conditie (value) VALUES ('werkbaar');
INSERT INTO enum_conditie (value) VALUES ('inspecteren');

CREATE TABLE bluswater.inspectie
(
  id                      SERIAL  NOT NULL PRIMARY KEY,
  brandkraan_nummer       VARCHAR NOT NULL,
  datum_aangemaakt        TIMESTAMP WITH TIME ZONE                                                              DEFAULT now(),
  datum_gewijzigd         TIMESTAMP WITH TIME ZONE,
  conditie                TEXT    NOT NULL REFERENCES enum_conditie (value) ON UPDATE CASCADE ON DELETE CASCADE DEFAULT 'inspecteren',
  inspecteur              TEXT,
  plaatsaanduiding        TEXT,
  plaatsaanduiding_anders TEXT,
  toegankelijkheid        TEXT,
  toegankelijkheid_anders TEXT,
  klauw                   TEXT,
  klauw_diepte            SMALLINT,
  klauw_anders            TEXT,
  werking                 TEXT,
  werking_anders          TEXT,
  opmerking               TEXT,
  foto                    TEXT,
  uitgezet_bij_pwn        BOOLEAN                                                                               DEFAULT FALSE,
  uitgezet_bij_gemeente   BOOLEAN                                                                               DEFAULT FALSE,
  opmerking_beheerder     TEXT,
  inlognaam               TEXT
);
CREATE INDEX inspectie_brandkraan_nummer_uindex
  ON bluswater.inspectie (brandkraan_nummer);

CREATE TABLE bluswater.gt_pk_metadata_table
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

INSERT INTO gt_pk_metadata_table VALUES ('bluswater', 'brandkraan_inspectie', 'id', 1, 'assigned', NULL);

CREATE OR REPLACE VIEW bluswater.brandkraan_inspectie AS 
 SELECT brandkraan_huidig_plus.nummer AS id,
    inspectie.id AS inspectie_id,
    brandkraan_huidig_plus.nummer,
    brandkraan_huidig_plus.geom,
    inspectie.datum_aangemaakt,
    inspectie.datum_gewijzigd,
        CASE
            WHEN (inspectie.datum_aangemaakt + brandkraan_huidig_plus.frequentie::double precision * '1 mon'::interval) < now() THEN 'inspecteren'::text
            WHEN (inspectie.datum_aangemaakt + (brandkraan_huidig_plus.frequentie - 3)::double precision * '1 mon'::interval) < now() AND (inspectie.datum_aangemaakt + brandkraan_huidig_plus.frequentie::double precision * '1 mon'::interval) > now() THEN 'binnenkort inspecteren'::text
            ELSE COALESCE(inspectie.conditie, 'inspecteren'::text)
        END AS conditie,
    inspectie.inspecteur,
    inspectie.plaatsaanduiding,
    inspectie.plaatsaanduiding_anders,
    inspectie.toegankelijkheid,
    inspectie.toegankelijkheid_anders,
    inspectie.klauw,
    inspectie.klauw_diepte,
    inspectie.klauw_anders,
    inspectie.werking,
    inspectie.werking_anders,
    inspectie.opmerking,
    inspectie.foto,
    inspectie.uitgezet_bij_pwn AS uit_gezet_bij_pwn,
    inspectie.uitgezet_bij_gemeente AS uit_gezet_bij_gemeente,
    inspectie.opmerking_beheerder,
    brandkraan_huidig_plus.inlognaam,
    brandkraan_huidig_plus.gemeentenaam
   FROM bluswater.brandkraan_huidig_plus
     LEFT JOIN bluswater.inspectie ON inspectie.id = (( SELECT leegfreq.id
           FROM bluswater.inspectie leegfreq
          WHERE leegfreq.brandkraan_nummer::text = brandkraan_huidig_plus.nummer::text
          ORDER BY leegfreq.datum_aangemaakt DESC
         LIMIT 1))
  WHERE brandkraan_huidig_plus.verwijderd = false;

CREATE OR REPLACE RULE brandkraan_inspectie_del AS
ON DELETE TO bluswater.brandkraan_inspectie DO INSTEAD NOTHING;

CREATE OR REPLACE RULE brandkraan_inspectie_ins AS
ON INSERT TO bluswater.brandkraan_inspectie DO INSTEAD NOTHING;

CREATE OR REPLACE RULE brandkraan_inspectie_upd AS
    ON UPDATE TO bluswater.brandkraan_inspectie DO INSTEAD  INSERT INTO bluswater.inspectie (brandkraan_nummer, conditie, inspecteur, plaatsaanduiding, plaatsaanduiding_anders, toegankelijkheid, toegankelijkheid_anders, klauw, klauw_diepte, klauw_anders, werking, werking_anders, opmerking, foto)
  VALUES (old.nummer, new.conditie, new.inspecteur, new.plaatsaanduiding, new.plaatsaanduiding_anders, new.toegankelijkheid, new.toegankelijkheid_anders, new.klauw, new.klauw_diepte, new.klauw_anders, new.werking, new.werking_anders, new.opmerking, new.foto)
  RETURNING inspectie.brandkraan_nummer,
    inspectie.id,
    inspectie.brandkraan_nummer,
    ( SELECT brandkraan_huidig_plus.geom
           FROM bluswater.brandkraan_huidig_plus
          WHERE inspectie.brandkraan_nummer::text = brandkraan_huidig_plus.nummer::text) AS geom,
    inspectie.datum_aangemaakt,
    inspectie.datum_gewijzigd,
    inspectie.conditie,
    inspectie.inspecteur,
    inspectie.plaatsaanduiding,
    inspectie.plaatsaanduiding_anders,
    inspectie.toegankelijkheid,
    inspectie.toegankelijkheid_anders,
    inspectie.klauw,
    inspectie.klauw_diepte,
    inspectie.klauw_anders,
    inspectie.werking,
    inspectie.werking_anders,
    inspectie.opmerking,
    inspectie.foto,
    inspectie.uitgezet_bij_pwn,
    inspectie.uitgezet_bij_gemeente,
    inspectie.opmerking_beheerder,
    ( SELECT brandkraan_huidig_plus.inlognaam
           FROM bluswater.brandkraan_huidig_plus
          WHERE inspectie.brandkraan_nummer::text = brandkraan_huidig_plus.nummer::text),
    ( SELECT brandkraan_huidig_plus.gemeentenaam
           FROM bluswater.brandkraan_huidig_plus
          WHERE inspectie.brandkraan_nummer::text = brandkraan_huidig_plus.nummer::text);

-- Views t.b.v. Jasper Reports
CREATE OR REPLACE VIEW bluswater.rapport_inspectie AS
  SELECT
    brandkraan_huidig_plus.nummer AS            id,
    inspectie.id                  AS            inspectie_id,
    brandkraan_huidig_plus.nummer,
    brandkraan_huidig_plus.geom,
    brandkraan_huidig_plus.type,
    brandkraan_huidig_plus.diameter,
    brandkraan_huidig_plus.postcode,
    brandkraan_huidig_plus.straat,
    brandkraan_huidig_plus.huisnummer,
    brandkraan_huidig_plus.capaciteit,
    brandkraan_huidig_plus.plaats,
    brandkraan_huidig_plus.gemeentenaam,
    inspectie.datum_aangemaakt,
    inspectie.datum_gewijzigd,
    GREATEST(datum_aangemaakt, datum_gewijzigd) mutatie,
    inspectie.conditie,
    inspectie.inspecteur,
    inspectie.plaatsaanduiding,
    inspectie.plaatsaanduiding_anders,
    inspectie.toegankelijkheid,
    inspectie.toegankelijkheid_anders,
    inspectie.klauw,
    inspectie.klauw_diepte,
    inspectie.klauw_anders,
    inspectie.werking,
    inspectie.werking_anders,
    inspectie.opmerking,
    inspectie.foto,
    inspectie.uitgezet_bij_pwn,
    inspectie.uitgezet_bij_gemeente,
    inspectie.opmerking_beheerder
  FROM bluswater.brandkraan_huidig_plus
    LEFT JOIN bluswater.inspectie ON inspectie.id = ((SELECT leegfreq.id
                                                      FROM bluswater.inspectie leegfreq
                                                      WHERE leegfreq.brandkraan_nummer :: TEXT =
                                                            brandkraan_huidig_plus.nummer :: TEXT
                                                      ORDER BY leegfreq.datum_aangemaakt DESC
                                                      LIMIT 1))
  WHERE brandkraan_huidig_plus.verwijderd = FALSE;
COMMENT ON VIEW bluswater.rapport_inspectie
IS 'Algemene view voor weergave in rapporten';

CREATE OR REPLACE VIEW bluswater.rapport_weekoverzicht AS
  SELECT
    *,
    btrim(
        concat(plaatsaanduiding, ' ', plaatsaanduiding_anders, ' ', toegankelijkheid, ' ', toegankelijkheid_anders, ' ',
               klauw, ' ', klauw_diepte, ' ', klauw_anders, ' ', werking, ' ', werking_anders)) AS resultaat
  FROM bluswater.rapport_inspectie
  WHERE date_part('week' :: TEXT, mutatie) = date_part('week' :: TEXT, now())
  ORDER BY mutatie;

CREATE OR REPLACE VIEW bluswater.rapport_inspectie_defect AS
  SELECT *
  FROM bluswater.rapport_inspectie
  WHERE (conditie ~~* 'afgekeurd' OR conditie ~~* 'werkbaar');

COMMENT ON VIEW bluswater.rapport_inspectie_defect
IS 'View voor afgekeurd en werkbaar, basis voor rapport vandaag pwn en gemeente';

CREATE OR REPLACE VIEW bluswater.rapport_inspectie_vandaag_pwn AS
  SELECT *
  FROM bluswater.rapport_inspectie_defect
  WHERE mutatie :: DATE = now() :: DATE
        AND (klauw IS NOT NULL
             OR klauw_anders IS NOT NULL
             OR werking IS NOT NULL
             OR werking_anders IS NOT NULL);

CREATE OR REPLACE VIEW bluswater.rapport_inspectie_vandaag_gemeente AS
  SELECT *
  FROM bluswater.rapport_inspectie_defect
  WHERE mutatie :: DATE = now() :: DATE
        AND (plaatsaanduiding IS NOT NULL
             OR plaatsaanduiding_anders IS NOT NULL
             OR toegankelijkheid IS NOT NULL
             OR toegankelijkheid_anders IS NOT NULL);			 

-- Alternatieve bluswatervoorzieningen
CREATE TABLE alternatieve_type
(
  id 			SMALLINT PRIMARY KEY NOT NULL,
  naam		 	VARCHAR(25)
);
COMMENT ON TABLE alternatieve_type IS 'Opzoeklijst voor alternatieve bluswatervoorzieningen';

CREATE TABLE alternatieve
(
  id 			SERIAL NOT NULL PRIMARY KEY,
  datum_aangemaakt        TIMESTAMP WITH TIME ZONE DEFAULT now(),
  datum_gewijzigd         TIMESTAMP WITH TIME ZONE,
  type_id		INTEGER,
  liters_per 	INTEGER,
  label			TEXT,
  geom 			geometry(Point,28992),
  CONSTRAINT 	altern_type_id_fk FOREIGN KEY (type_id) REFERENCES alternatieve_type (id)
);

CREATE INDEX alternatieve_geom_gist
  ON alternatieve
  USING btree
  (geom);

-- Create view straal met 120m afgekeurde brandkranen
CREATE OR REPLACE VIEW afgekeurd_binnen_straal AS 
 SELECT row_number() OVER (ORDER BY tot.bk_nummer) AS gid,
    tot.bk_nummer,
    tot.count,
    bk.geom
   FROM ( SELECT nearest.bk_nummer,
            count(nearest.bk_nummer) AS count
           FROM ( SELECT i.id AS bk_nummer,
                    i.b_gid,
                    st_distance(i.geom, i.b_geom) AS dist,
                    i.geom
                   FROM ( SELECT a.id,
                            b.id AS b_gid,
                            a.geom,
                            b.geom AS b_geom,
                            rank() OVER (PARTITION BY a.id ORDER BY (st_distance(a.geom, b.geom))) AS pos
                           FROM ( SELECT brandkraan_inspectie.id,
                                    brandkraan_inspectie.geom
                                   FROM brandkraan_inspectie
                                  WHERE brandkraan_inspectie.conditie = 'afgekeurd'::text) a,
                            ( SELECT brandkraan_inspectie.id,
                                    brandkraan_inspectie.geom
                                   FROM brandkraan_inspectie
                                  WHERE brandkraan_inspectie.conditie = 'afgekeurd'::text) b
                          WHERE a.id::text <> b.id::text) i
                  WHERE i.pos <= 5) nearest
          WHERE nearest.dist <= 120::double precision
          GROUP BY nearest.bk_nummer) tot
     JOIN brandkranen bk ON tot.bk_nummer::text = bk.nummer::text;
     
CREATE OR REPLACE VIEW bluswater.stavaza_gemeente AS 
 SELECT row_number() OVER (ORDER BY g.gemeentena) AS gid,
    g.gemeentena,
    count(s.conditie) FILTER (WHERE s.conditie = 'inspecteren'::text) AS inspecteren,
    count(s.conditie) FILTER (WHERE s.conditie = 'goedgekeurd'::text) AS goedgekeurd,
    count(s.conditie) FILTER (WHERE s.conditie = 'werkbaar'::text) AS werkbaar,
    count(s.conditie) FILTER (WHERE s.conditie = 'afgekeurd'::text) AS afgekeurd,
    count(s.conditie) FILTER (WHERE s.conditie = 'binnenkort inspecteren'::text) AS binnenkort_inspecteren,
    g.geom
   FROM bluswater.brandkraan_inspectie s
     LEFT JOIN algemeen.gemeente_zonder_wtr g ON st_intersects(s.geom, g.geom)
  GROUP BY g.gemeentena, g.geom;

-- Restricties voor opzoektabellen
REVOKE ALL ON TABLE brandkraan_huidig FROM GROUP oiv_write;
REVOKE ALL ON TABLE leiding_huidig FROM GROUP oiv_write;
REVOKE ALL ON TABLE alternatieve_type FROM GROUP oiv_write;
REVOKE ALL ON TABLE brandkranen FROM GROUP oiv_write;
REVOKE ALL ON TABLE leidingen FROM GROUP oiv_write;
REVOKE ALL ON TABLE afgekeurd_binnen_straal FROM GROUP oiv_write;