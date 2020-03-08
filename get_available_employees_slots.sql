
CREATE OR REPLACE FUNCTION get_available_employees_slots(
	service_ids text,
	staff_ids text,
	checking_date date,
	slot_interval integer DEFAULT 15)
    RETURNS time without time zone[]
    LANGUAGE 'plpgsql'

    COST 100
    VOLATILE 
    
AS $BODY$

declare
	service_id_list bigint [];
	staff bigint;
	staff_id_list bigint [];
	temp_time_slots time [];
	time_slots time [];
	start_time time;
	end_time time;
	temp_end_time time;
	day_of_week int;
	is_open boolean;
	found_office_hour text;
	services_duration int;
	found_booking_detail int;
BEGIN

	service_id_list := string_to_array(service_ids, ',');
	staff_id_list := string_to_array(staff_ids, ',');
	day_of_week := (SELECT (EXTRACT(DOW FROM checking_date) + 1));
	SELECT INTO services_duration sum(duration) FROM service where id = ANY(service_id_list);

	-- Check is business open or not for the day
	is_open := (SELECT true FROM business_hour where day_number = day_of_week and center_id = (select spa_center_id from employee where id = ANY(staff_id_list) LIMIT 1 OFFSET 0));
	if is_open is null then
		RAISE WARNING 'Businness is not open';
		return time_slots;
	end if;
	
	if services_duration is null then
		RAISE WARNING 'Services id % is not found', service_ids;
		return time_slots;
	end if;

	end_time := end_time - (services_duration * (interval '1 minute'));

	FOREACH staff IN ARRAY staff_id_list LOOP
		temp_time_slots := array[]::time[];
		
		-- Get Employee office hours
		SELECT INTO start_time, end_time
			MIN(TO_TIMESTAMP(concat(start_hour, ':' , start_minute), 'HH24:MI')::time),
			MAX(TO_TIMESTAMP(concat(end_hour, ':' , end_minute), 'HH24:MI')::time)
		FROM office_hour where employee_id = staff AND day_number = day_of_week;
		
		WHILE start_time <= end_time LOOP	
			temp_end_time := start_time + (services_duration * (interval '1 minute'));
			
			-- Check confict with booking
			found_booking_detail := (
				SELECT 
					count(*) 
				FROM  
					booking_detail 
				where
					( 
						TO_TIMESTAMP(concat(start_hour, ':' ,start_minute), 'HH24:MI')::time, 
						TO_TIMESTAMP(concat(end_hour, ':' ,end_minute), 'HH24:MI')::time 
					) OVERLAPS ( 
						start_time::time, 
						temp_end_time::time
					) AND
					employee_id = staff AND
					selected_date::date = checking_date::date
			);
			
			IF found_booking_detail = 0 THEN
				temp_time_slots := array_append(temp_time_slots, start_time);
			END IF;

			start_time := start_time + (slot_interval * (interval '1 minute'));
		END LOOP;
		RAISE NOTICE 'temp_time_slots = %', temp_time_slots;	
		time_slots := time_slots || temp_time_slots;
	END LOOP;

	-- Sort and unique Array
	return (SELECT ARRAY(
		SELECT DISTINCT temp_time_slots[s.i]
		FROM generate_series(array_lower(temp_time_slots,1), array_upper(temp_time_slots,1)) AS s(i)
		ORDER BY 1
	  ));
end;

$BODY$;
