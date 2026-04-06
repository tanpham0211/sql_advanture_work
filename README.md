# Analyze retail business Using SQL (BigQuery)

This project uses the AdventureWorks dataset, which simulates a retail business (bikes, accessories, etc.), including: **Sales data (orders), Sales data (orders), and Customer data**.

- **Author**: Pham Duy Tan
- **Tool Used**: SQL/BigQuery
---

## 📋 Table of Contents
1. Introduction
2. SQL Queries & Results
3. Recommendations

---

## ✨ Introduction
### 🎯 Objectives
- This project uses SQL to analyze retail business, base on Adventure Work dataset.
- The objective is to practice real-world SQL querying, compute key user behavior and e-commerce performance metrics, and translate raw session-level data into actionable business insights.

### 🧩 Project Objective
The main objectives of this project are:
* Analyze overall sales performance
* Track business growth over time
* Understand product-level performance
* Support business decisions such as marketing and inventory planning

### 📂 Dataset
- Source: Adventure Work 2019 (BigQuery Public Data)
- Main table:
  adventureworks2019.Sales.SalesOrderDetail
  adventureworks2019.Production.Product
  adventureworks2019.Production.ProductSubcategory

### ⚒️ Skills Demonstrated
- SQL: CTEs, window functions, JOIN, UNION, aggregate functions
- Customer behavior analysis: cohort analysis
- Business analytics: analyze sales performance, identify top-performing subcategories
- Business thinking: translating analytical results into insights relevant to decision-making

---

## 💻 SQL Queries & Results

### 📌 Q1. Calc Quantity of items, Sales value & Order quantity by each Subcategory **in L12M **

The purpose of this query:
- Analyzed last 12 months sales by product subcategory, including total revenue, quantity sold, and order volume.

```sql
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
```
- **Result**
<img width="635" height="107" alt="image" src="https://github.com/user-attachments/assets/e977de1d-5210-49a5-bb86-19c929dc06ab" />

### 📌 Q2. Calc **% YoY growth rate** by Category & release top 3 cat with highest grow rate
The purpose of this query:
- Calculated YoY growth by product category to identify top-performing segments and highlight business expansion opportunities.

```sql
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
  order by 5 desc 
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
      , dk
from rk_qty_diff 
where dk <=3
order by dk ;
```
- **Result**
<img width="633" height="565" alt="image" src="https://github.com/user-attachments/assets/a1d82214-82b6-4311-b130-9df797772a02" />

### 📌 Q3. Ranking Top 3 TeritoryID with biggest Order quantity of every year

The purpose of this query:
- Identified best-selling and underperforming products based on revenue and quantity to support product strategy decisions.

```sql
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
from sale_rank 
where rk in (1,2,3) 
;
```
- **Result**
<img width="785" height="648" alt="image" src="https://github.com/user-attachments/assets/6c869d5a-70dd-47dc-bbf6-94d45f8a8f88" />

### 📌 Q4. Calc Total Discount Cost belongs to Seasonal Discount **for each SubCategory**
The purpose of this query:
- Calculates the total discount cost per year and product subcategory for all sales orders that used a Seasonal Discount offer.

```sql
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
```
- **Result**
<img width="511" height="80" alt="image" src="https://github.com/user-attachments/assets/82296bb8-b1bc-4b42-a6b4-bf81c583fd0e" />

### 📌 Q5.**Retention rate** of Customer in 2014 with status of Successfully Shipped (Cohort Analysis)
The purpose of this query:
- Analyzes customer purchasing behavior in 2014 by tracking how many months after their first purchase month each customer continued to place orders.

```sql
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
```
- **Result**
<img width="484" height="54" alt="image" src="https://github.com/user-attachments/assets/392cb887-15c9-49ed-9ea1-8ef68d8cbd0c" />

### 📌 Q6. Trend of Stock level & MoM diff % by all product in 2011. If %gr rate is null then 0.
The purpose of this query:
- Analyzes monthly production quantities for each product in the year 2011 and calculates how production changed from one month to the previous month.

```sql
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
```
- **Result**
<img width="478" height="54" alt="image" src="https://github.com/user-attachments/assets/68d308eb-5e64-4e26-b8c4-336abbc4af4f" />

### 📌 Q7. Calc MoM Ratio of Stock / Sales in 2011 by product name
The purpose of this query:
-  Compares monthly sales quantities with monthly production quantities for each product in the year 2011, and calculates the ratio between production and sales.

```sql
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
```
- **Result**
<img width="386" height="296" alt="image" src="https://github.com/user-attachments/assets/d98c8880-8905-426f-809c-fb3061e9c7eb" />

### 📌 Q8. No of order and value at Pending status in 2014
The purpose of this query:
- Summarizes purchase order activity for the year 2014, focusing only on orders with Status = 1

```sql
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
```
- **Result**
<img width="881" height="109" alt="image" src="https://github.com/user-attachments/assets/d64aa493-d8af-4b10-b91c-e7e4c73532ef" />

---
| **Q8. Cohort map from product view → add-to-cart → purchase in January–March 2017** | Optimize the conversion funnel by improving product page clarity, strengthening calls-to-action, reducing checkout friction, and testing UX enhancements to increase conversion rates. |
