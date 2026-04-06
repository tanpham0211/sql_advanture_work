
-- Q1: Calc Quantity of items, Sales value & Order quantity by each Subcategory in L12M-----

select format_datetime('%b %Y', a.ModifiedDate) month
      ,c.Name
      ,sum(a.OrderQty) qty_item
      ,sum(a.LineTotal) total_sales
      ,count(distinct a.SalesOrderID) order_cnt
FROM `adventureworks2019.Sales.SalesOrderDetail` a 
left join `adventureworks2019.Production.Product` b
  on a.ProductID = b.ProductID
left join `adventureworks2019.Production.ProductSubcategory` c
  on b.ProductSubcategoryID = cast(c.ProductSubcategoryID as string)
where date(a.ModifiedDate) >=  (select date_sub(date(max(a.ModifiedDate)), INTERVAL 12 month)
                                from `adventureworks2019.Sales.SalesOrderDetail` ) -- filter L12M
group by 1,2
order by 2,1;

-- Q2: Calc % YoY growth rate by Category & release top 3 cat with highest grow rate. Can use metric: quantity_item. Round results to 2 decimal----

with 
sale_info as (
  SELECT 
      FORMAT_TIMESTAMP("%Y", a.ModifiedDate) as yr
      , c.Name
      , sum(a.OrderQty) as qty_item

  FROM `adventureworks2019.Sales.SalesOrderDetail` a 
  LEFT JOIN `adventureworks2019.Production.Product` b 
    on a.ProductID = b.ProductID
  LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c 
    on cast(b.ProductSubcategoryID as int) = c.ProductSubcategoryID
  GROUP BY 1,2
  ORDER BY 2 asc , 1 desc
),

sale_diff as (
  select 
  yr
  ,Name
  ,qty_item
  ,lead (qty_item) over (partition by Name order by yr desc) as prv_qty
  ,round(qty_item / (lead (qty_item) over (partition by Name order by yr desc)) -1,2) as qty_diff
  from sale_info
  order by qty_diff desc 
),

rk_qty_diff as (
  select 
    yr
    ,Name
    ,qty_item
    ,prv_qty
    ,qty_diff
    ,dense_rank() over( order by qty_diff desc) dk
  from sale_diff
)

select distinct Name
      , qty_item
      , prv_qty
      , qty_diff
from rk_qty_diff 
where dk <=3
order by dk ;


-- Q3: Ranking Top 3 TeritoryID with biggest Order quantity of every year. If theres TerritoryID with same quantity in a year, do not skip the rank number----

with 
sale_info as (
  select 
      FORMAT_TIMESTAMP("%Y", a.ModifiedDate) as yr
      , b.TerritoryID
      , sum(OrderQty) as order_cnt 
  from `adventureworks2019.Sales.SalesOrderDetail` a 
  LEFT JOIN `adventureworks2019.Sales.SalesOrderHeader` b 
    on a.SalesOrderID = b.SalesOrderID
  group by 1,2
),

sale_rank as (
  select 
      yr
      ,TerritoryID
      ,order_cnt
      ,dense_rank() over (partition by yr order by order_cnt desc) as rk 
  from sale_info 
)

select yr
    , TerritoryID
    , order_cnt
    , rk
    , dk
from sale_rank 
where rk in (1,2,3) 
;

-- Q4: Calc Total Discount Cost belongs to Seasonal Discount for each SubCategory----

select 
    FORMAT_TIMESTAMP("%Y", ModifiedDate)
    , Name
    , sum(disc_cost) as total_cost
from (
      select distinct a.ModifiedDate
      , c.Name
      , d.DiscountPct, d.Type
      , a.OrderQty * d.DiscountPct * UnitPrice as disc_cost 
      from `adventureworks2019.Sales.SalesOrderDetail` a
      LEFT JOIN `adventureworks2019.Production.Product` b on a.ProductID = b.ProductID
      LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c on cast(b.ProductSubcategoryID as int) = c.ProductSubcategoryID
      LEFT JOIN `adventureworks2019.Sales.SpecialOffer` d on a.SpecialOfferID = d.SpecialOfferID
      WHERE lower(d.Type) like '%seasonal discount%' 
)
group by 1,2;


-- Q5: Retention rate of Customer in 2014 with status of Successfully Shipped (Cohort Analysis)----

with 
info as (
  select  
      extract(month from ModifiedDate) as month_no
      , extract(year from ModifiedDate) as year_no
      , CustomerID
      , count(Distinct SalesOrderID) as order_cnt
  from `adventureworks2019.Sales.SalesOrderHeader`
  where FORMAT_TIMESTAMP("%Y", ModifiedDate) = '2014'
  and Status = 5
  group by 1,2,3
  order by 3,1 
),

row_num as (-- đánh số thứ tự các tháng họ mua hàng
  select 
      month_no
      ,year_no
      ,CustomerID
      ,order_cnt
      , row_number() over (partition by CustomerID order by month_no) as row_numb
  from info 
), 

first_order as (   -- lấy ra tháng đầu tiên của từng khách
  select 
      month_no
      ,year_no
      ,CustomerID
      ,order_cnt
  from row_num
  where row_numb = 1
), 

month_gap as (
  select 
      a.CustomerID
      , b.month_no as month_join
      , a.month_no as month_order
      , a.order_cnt
      , concat('M - ',a.month_no - b.month_no) as month_diff
  from info a 
  left join first_order b 
  on a.CustomerID = b.CustomerID
  order by 1,3
)

select month_join
      , month_diff 
      , count(distinct CustomerID) as customer_cnt
from month_gap
group by 1,2
order by 1,2;

-- Q6: Trend of Stock level & MoM diff % by all product in 2011. If %gr rate is null then 0. Round to 1 decimal----

with 
raw_data as (
  select
      extract(month from a.ModifiedDate) as mth 
      , extract(year from a.ModifiedDate) as yr 
      , b.Name
      , sum(StockedQty) as stock_qty
  from `adventureworks2019.Production.WorkOrder` a
  left join `adventureworks2019.Production.Product` b on a.ProductID = b.ProductID
  where FORMAT_TIMESTAMP("%Y", a.ModifiedDate) = '2011'
  group by 1,2,3
  order by 1 desc 
)

select  Name
      , mth, yr 
      , stock_qty
      , stock_prv
      , round(coalesce((stock_qty /stock_prv -1)*100 ,0) ,1) as diff
from (                                                                 
      select 
      mth,yr,Name
      ,stock_qty
      , lead (stock_qty) over (partition by Name order by mth desc) as stock_prv
      from raw_data
      )
order by 1 asc, 2 desc;


-- Q7: Calc MoM Ratio of Stock / Sales in 2011 by product name----

with 
sale_info as (
  select 
      extract(month from a.ModifiedDate) as mth 
     , extract(year from a.ModifiedDate) as yr 
     , a.ProductId
     , b.Name
     , sum(a.OrderQty) as sales
  from `adventureworks2019.Sales.SalesOrderDetail` a 
  left join `adventureworks2019.Production.Product` b 
    on a.ProductID = b.ProductID
  where FORMAT_TIMESTAMP("%Y", a.ModifiedDate) = '2011'
  group by 1,2,3,4
), 

stock_info as (
  select
      extract(month from ModifiedDate) as mth 
      , extract(year from ModifiedDate) as yr 
      , ProductId
      , sum(StockedQty) as stock_cnt
  from 'adventureworks2019.Production.WorkOrder'
  where FORMAT_TIMESTAMP("%Y", ModifiedDate) = '2011'
  group by 1,2,3
)

select
      a.mth
    , a.yr
    , a.ProductId
    , a.Name
    , a.sales
    , b.stock_cnt as stock  --(*)
    , round(coalesce(b.stock_cnt,0) / sales,2) as ratio
from sale_info a 
full join stock_info b 
  on a.ProductId = b.ProductId
and a.mth = b.mth 
and a.yr = b.yr
order by 1 desc, 7 desc;

-- Q8: No of order and value at Pending status in 2014---
select 
    extract (year from ModifiedDate) as yr
    , Status
    , count(distinct PurchaseOrderID) as order_Cnt 
    , sum(TotalDue) as value
from `adventureworks2019.Purchasing.PurchaseOrderHeader`
where Status = 1
and extract(year from ModifiedDate) = 2014
group by 1,2
;