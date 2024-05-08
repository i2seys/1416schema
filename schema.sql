CREATE EXTENSION if not exists plpython3u;
CREATE EXTENSION if not exists pgcrypto;
create type user_status as enum ('CREATOR', 'ADMIN', 'USER');
create type group_status as enum ('local', 'globals');
create table category(
 id serial
 primary key,
 name varchar(32) not null,
 name_en varchar(32),
 status boolean
);

create table shop(
 id serial
 primary key,
 name varchar(32) not null,
 name_en varchar(32),
 status boolean
);

create table metric(
 id serial
 primary key,
 name varchar(32) not null
 unique,
 name_en varchar(32)
);

create table currency(
 code varchar(3) not null
 primary key,
 name varchar(32) not null
 unique,
 code_en varchar(3),
 units integer,
 course double precision
);

create table user_account(
 id uuid not null
 primary key,
 email varchar(128) not null,
 registered_at timestamp,
 hashed_password varchar(1024) not null,
 is_active boolean not null,
 is_superuser boolean not null,
 is_verified boolean not null
);

create table product(
 id serial
 primary key,
 name varchar(32) not null,
 name_en varchar(32),
 id_category integer
 references category,
 fat double precision,
 protein double precision,
 carb double precision,
 calorie double precision
);

create table recipe(
 id serial
 primary key,
 name varchar(32) not null,
 name_en varchar(32),
 description varchar(128),
 portion integer,
 calories double precision
);

create table recipe_product_association(
 id_product integer not null
 references product
 on update cascade on delete cascade,
 id_recipe integer not null
 references recipe
 on update cascade on delete cascade,
 id_metric integer
 references metric,
 count integer,
 constraint idx_recipe_product
 unique (id_recipe, id_product),
 PRIMARY KEY (id_product, id_recipe)
);

create table "group"(
 id uuid not null
 primary key,
 name varchar(32),
 photo varchar(256),
 creation_date timestamp,
 status group_status
);

create table "check"(
 id uuid not null
 primary key
 unique,
 id_product integer not null
 references product,
 id_shop integer references shop,
 id_currency varchar(3)
 references currency,
 id_metric integer
 references metric,
 id_group uuid not null
 references "group" on update cascade on delete cascade,
 id_creator uuid not null,
 id_buyer uuid,
 date_create timestamp,
 date_close timestamp,
 description varchar(128),
 count integer,
 price integer,
 status boolean not null
);

create table target(
 id uuid not null
 primary key
 unique,
 id_category integer
 references category,
 id_shop integer
 references shop,
 id_currency varchar(3)
 references currency,
 id_group uuid not null
 references "group"
 on update cascade on delete cascade,
 id_creator uuid not null,
 id_buyer uuid,
 date_create timestamp,
 date_close timestamp,
 description varchar(128),
 name varchar(32),
 price_first integer,
 price_last integer,
 status boolean
);

create table group_token(
 id uuid not null
 primary key references "group"
 on update cascade on delete cascade,
 token varchar(12),
 date timestamp
);

create table account(
 uid serial
 primary key,
 login text not null,
 role text not null,
 pwhash text not null,
 real_name text not null,
 home_phone text not null
);

create table "user"(
 id uuid not null
 primary key references user_account (id)
 on update cascade on delete cascade,
 name varchar(32) not null,
 photo varchar(256),
 weight integer,
 height integer,
 age integer
);

create table group_user_association(
 id_user uuid not null
 references "user" (id)
 on update cascade on delete cascade,
 id_group uuid not null
 references "group"
 on update cascade on delete cascade,
 status user_status,
 date_invite timestamp,
 constraint idx_group_user
 unique (id_user, id_group),
 primary key (id_group,id_user)
);

CREATE INDEX index_check_id ON "check" USING hash (id_group);
CREATE INDEX index_target_id ON target USING hash (id_group);

CREATE OR REPLACE FUNCTION update_status_group()
 RETURNS TRIGGER AS
$$
BEGIN
 IF (NEW.name = '') THEN
 UPDATE "group"
 SET status = 'local'
 WHERE id = NEW.id;
 end if;
 IF (NEW.name != '') THEN
 UPDATE "group"
 SET status = 'globals'
 WHERE id = NEW.id;
 end if;
 RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create trigger trigger_for_group
 after insert
 on "group"
 for each row
execute procedure update_status_group();

CREATE OR REPLACE FUNCTION update_calorie()
 RETURNS TRIGGER AS
$$
BEGIN
 UPDATE recipe
 SET calories = (select product.calorie from product where id =
NEW.id_product) * NEW.count + recipe.calories
 WHERE recipe.id = NEW.id_recipe;
 RETURN NEW;
END;
$$ LANGUAGE plpgsql;

create trigger trigger_for_calorie
 after insert
 on recipe_product_association
 for each row
execute procedure update_calorie();

create or replace function calorie_counting()
returns trigger as $$
fat=TD["new"]["fat"]
protein=TD["new"]["protein"]
carb=TD["new"]["carb"]
TD["new"]["calorie"] = fat*9+protein*4+carb*4
return "MODIFY"
$$ LANGUAGE plpython3u;

create or replace trigger trigger_calorie_counting
BEFORE INSERT ON product
for each row EXECUTE FUNCTION calorie_counting();

create or replace function most_popular_product()
 RETURNS varchar as
$$
BEGIN
 return (select p.name
 from "check"
 join product p on id_product = p.id
 group by p.name
 order by count(p.name) desc
 limit 1);
end;
$$ language plpgsql;

create or replace procedure change_password(password Text) as
$$
BEGIN
 EXECUTE 'ALTER role current_user with PASSWORD ''' || password || '''';
 EXECUTE 'UPDATE account
 set pwhash = crypt(''' || password || ''', gen_salt(''md5''))
 where login = current_user';
END
$$ LANGUAGE plpgsql;

create or replace procedure create_check_time_interval(date_start timestamp,
date_long timestamp)
as
$$
BEGIN
 CREATE TEMPORARY TABLE check_time_interval(
 id uuid,
 id_product int,
 id_shop int,
 id_currency varchar(3),
 id_metric int,
 id_group uuid,
 id_creator uuid,
 id_buyer uuid,
 date_create timestamp,
 date_close timestamp,
 description varchar,
 count int,
 price int,
 status boolean
 );
 INSERT INTO check_time_interval
 SELECT *
 from "check"
 where "check".date_close between date_start and date_long;
end;
$$ language plpgsql;