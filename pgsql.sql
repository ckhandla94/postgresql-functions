
CREATE OR REPLACE FUNCTION public.get_available_slots(
	service_ids text,
	staff_id bigint,
	checking_date date,
	slot_interval integer DEFAULT 15)
    RETURNS time without time zone[]
    LANGUAGE 'plpgsql'

    COST 100
    VOLATILE 
    
AS $BODY$

declare
	service_id_list bigint [];
	time_slots time [];
	start_time time;
	end_time time;
	temp_end_time time;
	day_of_week int;
	is_open boolean;
	found_office_hour office_hour%ROWTYPE;
	services_duration int;
	found_booking_detail int;
BEGIN

	
	service_id_list := string_to_array(service_ids, ',');
	
	day_of_week := (SELECT (EXTRACT(DOW FROM checking_date) + 1));
		
	SELECT INTO found_office_hour * FROM office_hour where employee_id = staff_id AND day_number = day_of_week;
	SELECT INTO services_duration sum(duration) FROM service where id = ANY(service_id_list);

	if found_office_hour.start_hour is null then
		RAISE WARNING 'Employee id % is not found', staff_id;
		return time_slots;
	end if;
	
	is_open := (SELECT true FROM business_hour where day_number = day_of_week and center_id = (select spa_center_id from employee where id = staff_id));

	if is_open is null then
		RAISE WARNING 'Businness is not open';
		return time_slots;
	end if;
	
	if services_duration is null then
		RAISE WARNING 'Services id % is not found', service_ids;
		return time_slots;
	end if;
	
	start_time := TO_TIMESTAMP(concat(found_office_hour.start_hour, ':' , found_office_hour.start_minute), 'HH24:MI')::time;
	end_time := TO_TIMESTAMP(concat(found_office_hour.end_hour, ':' , found_office_hour.end_minute), 'HH24:MI')::time;
	end_time := end_time - (services_duration * (interval '1 minute'));

	WHILE start_time <= end_time LOOP	
		temp_end_time := start_time + (services_duration * (interval '1 minute'));
		
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
				employee_id = staff_id AND
				selected_date::date = checking_date::date
		);
			
		
		RAISE NOTICE 'service_ids = %', service_ids;	
		
		RAISE NOTICE 'time_slots = %, found_booking_detail = %', start_time, found_booking_detail;	
		
		If found_booking_detail = 0 then
			time_slots := array_append(time_slots, start_time);
		end if;
		start_time := start_time + (slot_interval * (interval '1 minute'));
	END LOOP;
	return time_slots;
end;

$BODY$;