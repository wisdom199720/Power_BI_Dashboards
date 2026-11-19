use north_star;

-- Create a staging table
Create Table orders_staging
like orders;


-- insert data
insert orders_staging
select * from orders;


-- check table
Select count(*) from orders_staging;


-- Data Cleaning
-- Search for duplicates
-- where customer rating was changed to 0 in excel to import data we replace with Null
-- Same for payment method
-- sales person "blank to null"
-- delivery days stays 0

With duplicates as
(
	select *, row_number()over(partition by order_date, customer_id, customer_name, customer_segment, region, industry, 
		salesperson, sales_channel, product_id, product, category, subcategory, quantity
		) as row_num
        from orders_staging
)
Select * from duplicates
where row_num > 1;

-- updating customer rating from 0 to null

update orders_staging
set customer_rating = null
where customer_rating = 0;

update orders_staging
set payment_method = null
where payment_method = "-";

update orders_staging
set salesperson = null
where salesperson = "blank";

-- Add new column named order_id
ALTER TABLE orders_staging
ADD COLUMN order_id varchar(6);

-- update it with a substring from orders
update orders_staging
set order_id = substring(orders, 5);

-- with duplicates as (
-- 			select *, row_number()over(partition by orders, order_id) as rownumber
--             from orders_staging
--             )
-- 		select count(*) from duplicates
--         where rownumber > 0;

select * 
from orders_staging;

select o.order_id, o.Product_id, o.salesperson,
		o.net_revenue_after_shipping,
        c.customer_id, c.customer_name
from orders_staging o
join customer_reference c on o.customer_id = c.customer_id;

select c.customer_id, c.customer_name,
		o.order_id, o.Product_id, o.salesperson,
		o.net_revenue_after_shipping
from customer_reference c
left join orders_staging o on c.customer_id = o.customer_id
where o.order_id is null;

select p.product_id,
	p.product,
    o.order_id
from product_reference p
Left join orders_staging o on p.product_id=o.product_id
where o.product_id is null;

-- customer with the highest order

with max_order as
	(
		select customer_id, count(customer_id) as total_order
		from orders_staging
		group by customer_id
	)
    select * from max_order
    order by total_order desc limit 1;
    
-- product ordered the most
with max_product as
	(
		select Product, 
				count(product_id) as total_product
			from orders_staging
			group by product
	)
    select *
    from max_product
    order by total_product desc;
    
-- Region with the highest revenue

select c.region, sum(Net_Revenue_After_Shipping) as total_revenue
from customer_reference c
left join orders_staging o on c.customer_id = o.customer_id
group by c.region;

-- what percentage of our total revenue comes from each product

with product_rev as
	(
		select product_id,
        sum(Net_Revenue_After_Shipping) as total_revenue
        from north_star.orders_staging
        group by product_id
	)
    select product_id,
		(total_revenue/ (select sum(total_revenue) from product_rev) * 100) as percentage_revenue,
        total_revenue
        from product_rev
        order by percentage_revenue desc;

-- customer with the highest revenue

with cte as 
	(
    select customer_id,
		sum(Net_Revenue_After_Shipping) as total_revenue
    from north_star.orders_staging
    group by customer_id
    )
    select *
    from cte
    order by total_revenue desc;
    
-- customer name  with number of orders

with no_of_orders as
	(
    select Customer_ID,
			count(Customer_ID) as total_orders
    from north_star.orders_staging
    group by Customer_ID
    )
    select *
    from no_of_orders
    order by total_orders desc;

-- sales person revenue
with cte as
	(
    select Salesperson,
    sum(Net_Revenue_After_Shipping) as total_revenue
    from north_star.orders_staging
    group by Salesperson 
    )
    select cte.salesperson,
    total_revenue,
    (total_revenue/(select sum(total_revenue) from cte) * 100) as percentage_revenue
    from cte
    order by total_revenue desc;


-- revenue grouping
with rev_grouping as
	(
    select product_id,
    sum(Net_Revenue_After_Shipping) as total_revenue
    from north_star.orders_staging
    group by product_id
    )
    select p.product_id,
    p.product,
    total_revenue,
    case
		when total_revenue > 400000 then 'high revenue'
        when total_revenue between 100000 and 400000 then 'Medium revenue'
        when total_revenue < 100000 then 'low_revenue'
	End as revenue_scale
    from rev_grouping r
    left join north_star.product_reference p on r.product_id = p.product_id 
    order by total_revenue desc;


--  for each region, show the customer who generated the highest revenue
-- (region, customer, revenue)
select region, customer_name, revenue
from
	(
	select region, customer_name, revenue,
		row_number()over(partition by region order by revenue desc) as row_num1
		from
		(
			select o.customer_id,
			c.customer_name,
			sum(Net_Revenue_After_Shipping) as revenue,
			c.region
			from north_star.orders_staging o
			left join north_star.customer_reference c on o.Customer_ID = c.Customer_ID
			group by o.customer_id, c.customer_name, c.region
		)
		as rank_num
	) as total
    where row_num1 = 1;


-- running total by date

with daily_revenue as (
	select 
		order_date,
        sum(net_revenue_after_shipping) as daily_revenue
        from north_star.orders_staging
        group by order_date
)
select
	order_date,
    daily_revenue,
    sum(daily_revenue) over (
		order by order_date rows between unbounded preceding and current row
    ) as running_total
from daily_revenue
order by order_date;
    
-- Count number of orders payment method based on customers

with payment as
(
	select 
    count(distinct case when Payment_Method = "Credit Card" then customer_id end) as credit_card,
    count(distinct case when Payment_Method = "EFT" then customer_id end) as EFT,
    count(distinct case when Payment_Method = "Purchase Order" then customer_id end) as purchase_order,
    count(distinct case when Payment_Method = "other" then customer_id end) as `others`,
    count(distinct case when Payment_Method is null then customer_id end)as `unknown`
    from north_star.orders_staging
)
select *, (credit_card+EFT+purchase_order+`others`+`unknown`)as total
from payment;

-- cancellation rate
with Cancellation_status as
(
	select 
    count(case when Cancellation_Status = "completed" then Customer_ID end) as Completed,
    count(case when Cancellation_status = "Cancelled" then Customer_ID end) as Cancelled
    from north_star.orders_staging
)

select *, (Cancelled * 100/(completed + cancelled)) as cancellation_rate
from Cancellation_status;

-- returned rate
select distinct Returned
from north_star.orders_staging;

with returned as
(
	select
    count(case when Returned = "Yes" then Product_ID end) as yes,
    count(case when Returned = "No" then Product_ID end) as `no`
    from north_star.orders_staging
)
select *, (yes * 100/(yes + `no`)) as return_rate
from returned;

-- return rate by product

with returned as
(
	select Product_ID,
    count(case when Returned = "Yes" then Product_ID end) as yes,
    count(case when Returned = "No" then Product_ID end) as `no`
    from north_star.orders_staging
    group by Product_ID
)
select p.Product, r.yes, r.`no`, (yes * 100/(yes + `no`)) as return_rate
from returned r
left join north_star.product_reference p on r.Product_ID = p.Product_ID;


select
	Salesperson, 
	count(*)
from north_star.orders_staging
group by Salesperson;

with cte as
(
	select Salesperson,
    case when salesperson is null then 'Unknown' else salesperson end as sales_person
    from north_star.orders_staging
	group by salesperson
)
select *
from cte;


select Delivery_Days, count(Delivery_Days) as count
from north_star.orders_staging
group by Delivery_Days;

select *
from north_star.orders_staging
where Cancellation_Status = "cancelled";

select
    avg(delivery_days) as average_delivery_days,
    count(case when returned = "yes" then returned end)/count(returned) as returned_rate,
    count(case when cancellation_status = "cancelled" then Cancellation_Status 
    end)/count(Cancellation_Status) as cancellation_rate
from north_star.orders_staging;


-- deductions after cancellation and returns
select sum(Net_Revenue_After_Shipping) as revenue
from north_star.orders_staging
where Cancellation_Status = "Completed" and Returned = "No";


select 
sum(
	Case
	when cancellation_status = "completed" and returned = "No"
	Then Net_revenue_after_shipping
	end)*(100/sum(Net_Revenue_After_Shipping)) as percentage_rev
from  north_star.orders_staging;


select 
Product,
sum(
	case
    when cancellation_status = "completed" and returned = "No"
    Then Net_revenue_after_shipping
    end) as rev,
sum(
	case
    when cancellation_status = "completed" and returned = "No"
    Then Net_revenue_after_shipping
    end)*(100/sum(Net_Revenue_After_Shipping)) as percentage_rev_per_product,
sum(
	case
    when cancellation_status = "cancelled" or returned = "Yes"
    Then Net_revenue_after_shipping
    end) as rev_lost_by_product,
sum(
    case 
    when cancellation_status = "completed" and returned = "no"
    then quantity end
) as units_sold,
sum(
	case 
    when cancellation_status = "cancelled" or returned = "Yes"
    then quantity end
) as qty_retunred
from north_star.orders_staging
group by Product order by rev;


select 
sum(
	case 
    when cancellation_status = "completed" and returned = "no"
    then Net_Revenue_After_Shipping end
)
from north_star.orders_staging;

select count(Cancellation_Status)
from north_star.orders_staging
group by Cancellation_Status;


-- Return and cancellation rates

select
	product,
    100.0 * sum(
    case when cancellation_status = 'cancelled' then 1 else 0 end
    )/count(cancellation_status) as cancellation_rate,
    100.0 * sum(
    case when returned = 'yes' then 1 else 0 end
    )/count(returned) as return_rate
from north_star.orders_staging
group by product
