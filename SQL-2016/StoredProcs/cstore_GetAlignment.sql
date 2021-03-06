/*
	CSIL - Columnstore Indexes Scripts Library for SQL Server 2016: 
	Columnstore Alignment - Shows the alignment (ordering) between the different Columnstore Segments
	Version: 1.5.0, August 2017

	Copyright 2015-2017 Niko Neugebauer, OH22 IS (http://www.nikoport.com/columnstore/), (http://www.oh22.is/)

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

/*
Known Issues & Limitations: 
	- no support for Multi-Dimensional Segment Clustering in this version

Changes in 1.0.2
	+ Added schema information and quotes for the table name

Changes in 1.0.4
	+ Added new parameter for filtering on the schema - @schemaName

Changes in 1.1.0
	+ Added new parameter for filtering on the object id - @objectId
	* Changed constant creation and dropping of the stored procedure to 1st time execution creation and simple alteration after that
	* The description header is copied into making part of the function code that will be stored on the server. This way the CISL version can be easily determined.
	* Added support for DROP TABLE IF EXISTS construct for the temporary table inside the code

Changes in 1.2.0
	+ Included support for the temporary tables with Columnstore Indexes (global & local)

Changes in 1.3.0
	+ Added support InMemory Columnstore Indexes
	+ Added support for the Index Location (Disk-Based, InMemory)
	+ Added new parameter for filtering the indexes, based on their location (Disk-Based or In-Memory) - @indexLocation
	- Fixed bug with non-functioning @objectId parameter

Changes in 1.3.1
	- Added support for Databases with collations different to TempDB

Changes in 1.4.1
	+ Added support for the SP1 which allows support of Columnstore Indexes on any edition

Changes in 1.5.0
	+ Added new parameter that allows to filter the results by specific partition number (@partitionNumber)
	+ Added new parameter for the searching precise name of the object (@preciseSearch)
	+ Added new parameter for the identifying the object by its object_id (@objectId)
	+ Expanded search of the schema to include the pattern search with @preciseSearch = 0
	+ Added new parameter for showing the number of distinct values within the segments, the percentage related to the total number of the rows within table/partition and the overall recommendation number (@showSegmentAnalysis)
	+ Added new parameter for showing the frequency of the column usage as predicates during querying (@scanExecutionPlans), which results are included in the overall recommendation for segment elimination
	+ Added information on the Predicate Pushdown support (it will be showing results depending on the used edition) - column [Predicate Pushdown]
*/

declare @SQLServerVersion nvarchar(128) = cast(SERVERPROPERTY('ProductVersion') as NVARCHAR(128)), 
		@SQLServerEdition nvarchar(128) = cast(SERVERPROPERTY('Edition') as NVARCHAR(128));
declare @errorMessage nvarchar(512);

-- Ensure that we are running SQL Server 2016
if substring(@SQLServerVersion,1,CHARINDEX('.',@SQLServerVersion)-1) <> N'13'
begin
	set @errorMessage = (N'You are not running a SQL Server 2016. Your SQL Server version is ' + @SQLServerVersion);
	Throw 51000, @errorMessage, 1;
end

IF EXISTS (SELECT 1 WHERE SERVERPROPERTY('EngineEdition') <> 3 AND cast(SERVERPROPERTY('ProductLevel') as nvarchar(128)) NOT LIKE 'SP%')
begin
	set @errorMessage = (N'Your SQL Server 2016 Edition is not an Enterprise or a Developer Edition or your are not running Service Pack 1 or later for SQL Server 2016. Your are running a ' + @SQLServerEdition);
	Throw 51000, @errorMessage, 1;
end
--------------------------------------------------------------------------------------------------------------------
IF NOT EXISTS (select * from sys.objects where type = 'p' and name = 'cstore_GetAlignment' and schema_id = SCHEMA_ID('dbo') )
	exec ('create procedure dbo.cstore_GetAlignment as select 1');
GO

/*
	CSIL - Columnstore Indexes Scripts Library for SQL Server 2016: 
	Columnstore Alignment - Shows the alignment (ordering) between the different Columnstore Segments
	Version: 1.5.0, August 2017
*/
alter procedure dbo.cstore_GetAlignment(
-- Params --
	@schemaName nvarchar(256) = NULL,		-- Allows to show data filtered down to the specified schema
	@tableName nvarchar(256) = NULL,		-- Allows to show data filtered down to 1 particular table
	@preciseSearch bit = 0,					-- Defines if the schema and data search with the parameters @schemaName & @tableName will be precise or pattern-like
	@showSegmentAnalysis BIT = 0,			-- Allows showing the overall recommendation for aligning order for each table/partition
	@countDistinctValues BIT = 0,			-- Allows showing the number of distinct values within the segments, the percentage related to the total number of the rows within table/partition (@countDistinctValues)
	@scanExecutionPlans BIT = 0,			-- Allows showing the frequency of the column usage as predicates during querying (@scanExecutionPlans), which results is included in the overall recommendation for segment elimination
	@indexLocation varchar(15) = NULL,		-- Allows to filter Columnstore Indexes based on their location: Disk-Based & In-Memory
	@objectId int = NULL,					-- Allows to idenitfy a table thorugh the ObjectId
	@showPartitionStats bit = 1,			-- Shows alignment statistics based on the partition
	@partitionNumber int = 0,				-- Allows to filter data on a specific partion. Works only if @showPartitionDetails is set = 1 
	@showUnsupportedSegments bit = 1,		-- Shows unsupported Segments in the result set
	@columnName nvarchar(256) = NULL,		-- Allows to show data filtered down to 1 particular column name
	@columnId int = NULL					-- Allows to filter one specific column Id
-- end of --
) as 
begin

	set nocount on;

	DROP TABLE IF EXISTS #column_store_segments;

	SELECT SchemaName, TableName, object_id, partition_number, hobt_id, partition_id, column_id, segment_id, min_data_id, max_data_id
	INTO #column_store_segments
	FROM ( select object_schema_name(part.object_id) as SchemaName, object_name(part.object_id) as TableName, part.object_id, part.partition_number, part.hobt_id, part.partition_id, seg.column_id, seg.segment_id, seg.min_data_id, seg.max_data_id
				FROM sys.column_store_segments seg
				INNER JOIN sys.partitions part
				   ON seg.hobt_id = part.hobt_id and seg.partition_id = part.partition_id
		union all
		select object_schema_name(part.object_id,db_id('tempdb')) as SchemaName, object_name(part.object_id,db_id('tempdb')) as TableName, part.object_id, part.partition_number, part.hobt_id, part.partition_id, seg.column_id, seg.segment_id, seg.min_data_id, seg.max_data_id
				FROM tempdb.sys.column_store_segments seg
				INNER JOIN tempdb.sys.partitions part
				   ON seg.hobt_id = part.hobt_id and seg.partition_id = part.partition_id
		) as Res
		OPTION (FORCE ORDER);

	ALTER TABLE #column_store_segments
	ADD UNIQUE (hobt_id, partition_id, column_id, min_data_id, segment_id);

	ALTER TABLE #column_store_segments
	ADD UNIQUE (hobt_id, partition_id, column_id, max_data_id, segment_id);

	DROP TABLE IF EXISTS #SegmentAlignmentResults;

	with cteSegmentAlignment as (
		select  part.object_id,  
				case ind.data_space_id when 0 then 'In-Memory' else 'Disk-Based' end as 'Location',				
				quotename(object_schema_name(part.object_id)) + '.' + quotename(object_name(part.object_id)) as TableName,
				case @showPartitionStats when 1 then part.partition_number else 1 end as partition_number, 
				seg.partition_id, seg.column_id, cols.name as ColumnName, tp.name as ColumnType,
				seg.segment_id, 
				CONVERT(BIT, MAX(CASE WHEN filteredSeg.segment_id IS NOT NULL THEN 1 ELSE 0 END)) AS hasOverlappingSegment
			from sys.column_store_segments seg
				inner join sys.partitions part
					on seg.hobt_id = part.hobt_id and seg.partition_id = part.partition_id 
				inner join sys.indexes ind
					on part.object_id = ind.object_id and ind.type in (5,6)
				inner join sys.columns cols
					on part.object_id = cols.object_id and (seg.column_id = cols.column_id + case ind.data_space_id when 0 then 1 else 0 end )
				inner join sys.types tp
					on cols.system_type_id = tp.system_type_id and cols.user_type_id = tp.user_type_id
				outer apply (
					SELECT TOP 1 otherSeg.segment_id
					FROM #column_store_segments otherSeg WITH (FORCESEEK)
					WHERE seg.hobt_id = otherSeg.hobt_id 
							AND seg.partition_id = otherSeg.partition_id 
							AND seg.column_id = otherSeg.column_id
							AND seg.segment_id <> otherSeg.segment_id
							AND (seg.min_data_id < otherSeg.min_data_id and seg.max_data_id > otherSeg.min_data_id )  -- Scenario 1 
					UNION ALL
					SELECT TOP 1 otherSeg.segment_id
					FROM #column_store_segments otherSeg WITH (FORCESEEK)
					WHERE seg.hobt_id = otherSeg.hobt_id 
							AND seg.partition_id = otherSeg.partition_id 
							AND seg.column_id = otherSeg.column_id
							AND seg.segment_id <> otherSeg.segment_id
							AND (seg.min_data_id < otherSeg.max_data_id and seg.max_data_id > otherSeg.max_data_id )  -- Scenario 2 
				) filteredSeg
			where    (@preciseSearch = 0 AND (@tableName is null or object_name (part.object_id) like '%' + @tableName + '%') 
					  OR @preciseSearch = 1 AND (@tableName is null or object_name (part.object_id) = @tableName) )
				 AND (@preciseSearch = 0 AND (@schemaName is null or object_schema_name( part.object_id ) like '%' + @schemaName + '%')
					  OR @preciseSearch = 1 AND (@schemaName is null or object_schema_name( part.object_id ) = @schemaName))
				 AND (ISNULL(@objectId,part.object_id) = part.object_id)
				 AND partition_number = case @partitionNumber when 0 then partition_number else @partitionNumber end
				 AND ind.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else ind.data_space_id end, ind.data_space_id )
				--AND exists (select *
				--		from sys.column_store_row_groups rg
				--		where seg.segment_id = rg.row_group_id 
				--			AND part.object_id = rg.object_id
				--			AND rg.state = 3)
			group by part.object_id, ind.data_space_id, case @showPartitionStats when 1 then part.partition_number else 1 end, seg.partition_id, seg.column_id, cols.name, tp.name, seg.segment_id
		UNION ALL
		select  part.object_id,  
				case ind.data_space_id when 0 then 'In-Memory' else 'Disk-Based' end as 'Location',
				quotename(object_schema_name(part.object_id,db_id('tempdb'))) + '.' + quotename(object_name(part.object_id,db_id('tempdb'))) as TableName,
				case @showPartitionStats when 1 then part.partition_number else 1 end as partition_number, 
				seg.partition_id, seg.column_id, cols.name COLLATE DATABASE_DEFAULT as ColumnName, tp.name COLLATE DATABASE_DEFAULT as ColumnType,
				seg.segment_id, 
				CONVERT(BIT, MAX(CASE WHEN filteredSeg.segment_id IS NOT NULL THEN 1 ELSE 0 END)) AS hasOverlappingSegment
			from tempdb.sys.column_store_segments seg
				inner join tempdb.sys.partitions part
					on seg.hobt_id = part.hobt_id and seg.partition_id = part.partition_id 
				inner join tempdb.sys.indexes ind
					on part.object_id = ind.object_id and ind.type in (5,6)
				inner join tempdb.sys.columns cols
					on part.object_id = cols.object_id and seg.column_id = cols.column_id
				inner join tempdb.sys.types tp
					on cols.system_type_id = tp.system_type_id and cols.user_type_id = tp.user_type_id
				outer apply (
					SELECT TOP 1 otherSeg.segment_id
					FROM #column_store_segments otherSeg --WITH (FORCESEEK)
					WHERE seg.hobt_id = otherSeg.hobt_id 
							AND seg.partition_id = otherSeg.partition_id 
							AND seg.column_id = otherSeg.column_id
							AND seg.segment_id <> otherSeg.segment_id
							AND (seg.min_data_id < otherSeg.min_data_id and seg.max_data_id > otherSeg.min_data_id )  -- Scenario 1 
					UNION ALL
					SELECT TOP 1 otherSeg.segment_id
					FROM #column_store_segments otherSeg --WITH (FORCESEEK)
					WHERE seg.hobt_id = otherSeg.hobt_id 
							AND seg.partition_id = otherSeg.partition_id 
							AND seg.column_id = otherSeg.column_id
							AND seg.segment_id <> otherSeg.segment_id
							AND (seg.min_data_id < otherSeg.max_data_id and seg.max_data_id > otherSeg.max_data_id )  -- Scenario 2 
				) filteredSeg
			where (@preciseSearch = 0 AND (@tableName is null or object_name (part.object_id,db_id('tempdb')) like '%' + @tableName + '%') 
					  OR @preciseSearch = 1 AND (@tableName is null or object_name (part.object_id,db_id('tempdb')) = @tableName) )
				 AND (@preciseSearch = 0 AND (@schemaName is null or object_schema_name( part.object_id,db_id('tempdb') ) like '%' + @schemaName + '%')
					  OR @preciseSearch = 1 AND (@schemaName is null or object_schema_name( part.object_id,db_id('tempdb') ) = @schemaName))
				 AND (ISNULL(@objectId,part.object_id) = part.object_id)
				 AND ind.data_space_id = isnull( case @indexLocation when 'In-Memory' then 0 when 'Disk-Based' then 1 else ind.data_space_id end, ind.data_space_id )
				 AND partition_number = case @partitionNumber when 0 then partition_number else @partitionNumber end				
			group by part.object_id, ind.data_space_id, case @showPartitionStats when 1 then part.partition_number else 1 end, seg.partition_id, seg.column_id, cols.name, tp.name, seg.segment_id

	)
	select TableName, Location, partition_number as 'Partition', cte.column_id as 'Column Id', cte.ColumnName, 
		cte.ColumnType,
		case cte.ColumnType when 'numeric' then 'not supported' 
							when 'datetimeoffset' then 'not supported' 
							when 'char' then 'not supported' 
							when 'nchar' then 'not supported' 
							when 'varchar' then 'not supported' 
							when 'nvarchar' then 'not supported' 
							when 'sysname' then 'not supported' 
							when 'binary' then 'not supported' 
							when 'varbinary' then 'not supported' 
							when 'uniqueidentifier' then 'not supported' 
			else 'OK' end as 'Segment Elimination',
		case cte.ColumnType when 'numeric' then 'not supported' 
						when 'datetimeoffset' then 'not supported' 
						when 'char' then CASE WHEN SERVERPROPERTY('EngineEdition') = 3 THEN 'OK' ELSE 'not supported' END
						when 'nchar' then CASE WHEN SERVERPROPERTY('EngineEdition') = 3 THEN 'OK' ELSE 'not supported' END
						when 'varchar' then CASE WHEN SERVERPROPERTY('EngineEdition') = 3 THEN 'OK' ELSE 'not supported' END
						when 'nvarchar' then CASE WHEN SERVERPROPERTY('EngineEdition') = 3 THEN 'OK' ELSE 'not supported' END
						when 'sysname' then CASE WHEN SERVERPROPERTY('EngineEdition') = 3 THEN 'OK' ELSE 'not supported' END
						when 'binary' then 'not supported' 
						when 'varbinary' then 'not supported' 
						when 'uniqueidentifier' then 'not supported' 
			else 'OK' end as [Predicate Pushdown],
		sum(CONVERT(INT, hasOverlappingSegment)) as [Dealigned Segments],
		count(*) as [Total Segments],
		100 - cast( sum(CONVERT(INT, hasOverlappingSegment)) * 100.0 / (count(*)) as Decimal(6,2)) as [Segment Alignment %]
		INTO #SegmentAlignmentResults
		from cteSegmentAlignment cte
		where ((@showUnsupportedSegments = 0 and cte.ColumnType COLLATE DATABASE_DEFAULT not in ('numeric','datetimeoffset','char', 'nchar', 'varchar', 'nvarchar', 'sysname','binary','varbinary','uniqueidentifier') ) 
			  OR @showUnsupportedSegments = 1)
			  and cte.ColumnName COLLATE DATABASE_DEFAULT = isnull(@columnName,cte.ColumnName COLLATE DATABASE_DEFAULT)
			  and cte.column_id = isnull(@columnId,cte.column_id)
		group by TableName, Location, partition_number, cte.column_id, cte.ColumnName, cte.ColumnType
		order by TableName, partition_number, cte.column_id;

	--- *****************************************************
	IF @showSegmentAnalysis = 1 
	BEGIN

		DECLARE @alignedColumnList NVARCHAR(MAX) = NULL;
		DECLARE @alignedColumnNamesList NVARCHAR(MAX) = NULL;
		DECLARE @alignedTable NVARCHAR(128) = NULL,
				@alignedPartition INT = NULL,
				@partitioningClause NVARCHAR(500) = NULL;

		DROP TABLE IF EXISTS #DistinctCounts;
		CREATE TABLE #DistinctCounts(
			TableName SYSNAME NOT NULL,
			PartitionId INT NOT NULL,
			ColumnName SYSNAME NOT NULL,
			DistinctCount BIGINT NOT NULL,
			TotalRowCount BIGINT NOT NULL
		);

		DECLARE alignmentTablesCursor CURSOR LOCAL FAST_FORWARD FOR
			SELECT DISTINCT TableName, [Partition]
				FROM #SegmentAlignmentResults;

		OPEN alignmentTablesCursor  

		FETCH NEXT FROM alignmentTablesCursor   
			INTO @alignedTable, @alignedPartition;

		WHILE @@FETCH_STATUS = 0  
		BEGIN  
			IF @countDistinctValues = 1
			BEGIN
				-- Define Partitioning Clause when showing partitioning information
				SET @partitioningClause = '';
				SELECT @partitioningClause = 'WHERE $PARTITION.[' + pf.name + ']([' + cols.name + ']) = ' + CAST(@alignedPartition AS VARCHAR(8))
 								 FROM sys.indexes ix
								 INNER JOIN sys.partition_schemes ps on ps.data_space_id = ix.data_space_id
								 INNER JOIN sys.partition_functions pf on pf.function_id = ps.function_id 
								INNER JOIN sys.index_columns ic	
									ON ic.object_id = ix.object_id AND ix.index_id = ic.index_id
								INNER JOIN sys.all_columns cols
									ON ic.column_id = cols.column_id AND ic.object_id = cols.object_id 
								WHERE ix.object_id = object_id(@alignedTable)
									AND ic.partition_ordinal = 1 AND @showPartitionStats = 1;
		
				-- Get the list with COUNT(DISTINCT [ColumnName])
				SELECT @alignedColumnList = STUFF((
					SELECt ', COUNT( DISTINCT ' + QUOTENAME(name) + ') as [' + name + ']'
						FROM sys.columns cols
						WHERE OBJECT_ID(@alignedTable) = cols.object_id 
							AND cols.name = isnull(@columnName,cols.name)
							AND cols.column_id = isnull(@columnId,cols.column_id)
						ORDER BY cols.column_id DESC
						FOR XML PATH('')
					), 1, 1, '');
	
				SELECT @alignedColumnNamesList = STUFF((
					SELECt ', [' + name + ']'
						FROM sys.columns cols
						WHERE OBJECT_ID(@alignedTable) = cols.object_id 
							AND cols.name = isnull(@columnName,cols.name)
							AND cols.column_id = isnull(@columnId,cols.column_id)
						ORDER BY cols.column_id DESC
						FOR XML PATH('')
					), 1, 1, '');

				-- Insert Count(*) and COUNT(DISTINCT*) into the #DistinctCounts table
				EXEC ( N'INSERT INTO #DistinctCounts ' +
						'SELECT ''' + @alignedTable + ''' as TableName, ' + @alignedPartition + ' as PartitionNumber, ColumnName, DistinctCount, __TotalRowCount__ as TotalRowCount ' +
						'	FROM (SELECT ''DistCount'' as [__Op__], COUNT(*) as __TotalRowCount__, ' + @alignedColumnList + 
										 ' FROM ' + @alignedTable + @partitioningClause + ') res ' +
						' UNPIVOT ' +
						'	  ( DistinctCount FOR ColumnName IN(' + @alignedColumnNamesList + ') ' + 
						'	  ) AS finalResult;' );
			END

			FETCH NEXT FROM alignmentTablesCursor   
				INTO @alignedTable, @alignedPartition;
		END

		CLOSE alignmentTablesCursor;  
		DEALLOCATE alignmentTablesCursor;
	
		-- Create table storing results of the access via cached execution plans
		DROP TABLE IF EXISTS #CachedAccessToColumnstore;
		CREATE TABLE #CachedAccessToColumnstore(
			[Schema] SYSNAME NOT NULL,
			[Table] SYSNAME NOT NULL,
			[TableName] SYSNAME NOT NULL,
			[ColumnName] SYSNAME NOT NULL,
			[ScanFrequency] BIGINT,
			[ScanRank] DECIMAL(16,6)
		);

		-- Scan cached execution plans and extract the frequency with which the table columns are searched
		IF @scanExecutionPlans = 1
		BEGIN
			
			-- Extract information from the cached execution plans to determine the frequency of the used(pushed down) predicates against Columnstore Indexes
			;WITH XMLNAMESPACES (DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan')   
			INSERT INTO #CachedAccessToColumnstore
			SELECT [Schema], 
				   [Table], 
				   [Schema] + '.' + [Table] as TableName, 
				   [Column] as ColumnName, 
				   SUM(execution_count) as ScanFrequency,
				   Cast(0. as Decimal(16,6)) as ScanRank
				FROM (
					SELECT x.value('(@Database)[1]', 'nvarchar(128)') AS [Database],
						   x.value('(@Schema)[1]', 'nvarchar(128)') AS [Schema],
						   x.value('(@Table)[1]', 'nvarchar(128)') AS [Table],
						   x.value('(@Alias)[1]', 'nvarchar(128)') AS [Alias],
						   x.value('(@Column)[1]', 'nvarchar(128)') AS [Column],
						   xmlRes.execution_count			   
						FROM (
							SELECT dm_exec_query_plan.query_plan,
								   dm_exec_query_stats.execution_count
								FROM sys.dm_exec_query_stats
									CROSS APPLY sys.dm_exec_sql_text(dm_exec_query_stats.sql_handle)
									CROSS APPLY sys.dm_exec_query_plan(dm_exec_query_stats.plan_handle)
								WHERE query_plan.exist('//RelOp//IndexScan//Object[@Storage = "ColumnStore"]') = 1
									  AND query_plan.exist('//RelOp//IndexScan//Predicate//Compare//ScalarOperator//Identifier//ColumnReference') = 1
						) xmlRes
							CROSS APPLY xmlRes.query_plan.nodes('//RelOp//IndexScan//Predicate//Compare//ScalarOperator//Identifier//ColumnReference') x1(x) --[@Database = "[' + @dbName + ']"]	
							WHERE 
								-- Avoid Inter-column Search references since they are not supporting Segment Elimination
								NOT (query_plan.exist('(//RelOp//IndexScan//Predicate//Compare//ScalarOperator//Identifier//ColumnReference[@Table])[1]') = 1
									AND query_plan.exist('(//RelOp//IndexScan//Predicate//Compare//ScalarOperator//Identifier//ColumnReference[@Table])[2]') = 1 
									AND x.value('(@Table)[1]', 'nvarchar(128)') = x.value('(@Table)[2]', 'nvarchar(128)') )
								) res
				WHERE res.[Database] = QUOTENAME(DB_NAME()) AND res.[Schema] IS NOT NULL AND res.[Table] IS NOT NULL
					AND res.[Column] COLLATE DATABASE_DEFAULT = isnull(@columnName,res.[Column])
				GROUP BY [Schema], [Table], [Column];

			-- Distribute Rank based on the values between 0 & 100
			UPDATE #CachedAccessToColumnstore
				SET ScanRank = ScanFrequency * 100. / (SELECT MAX(ScanFrequency) FROM #CachedAccessToColumnstore);
		END

		-- Deliver the final result
		SELECT res.*, cnt.DistinctCount, cnt.TotalRowCount, 
			CAST(cnt.DistinctCount * 100. / CASE cnt.TotalRowCount WHEN 0 THEN 1 ELSE cnt.TotalRowCount END  as Decimal(8,3)) as [PercDistinct],
			ISNULL(ScanFrequency,0) AS ScanFrequency,
			DENSE_RANK() OVER ( PARTITION BY res.[TableName], [Partition] 
						  ORDER BY ISNULL(ScanRank,-100) + 
								CASE WHEN [DistinctCount] < [Total Segments] OR [DistinctCount] < 2 THEN - 100 ELSE 0 END +
								( ISNULL(cnt.DistinctCount,0) * 100. / CASE ISNULL(cnt.TotalRowCount,0) WHEN 0 THEN 1 ELSE cnt.TotalRowCount END) 
								- CASE [Segment Elimination] WHEN 'OK' THEN 0. ELSE 1000. END
								DESC ) AS [Recommendation]		
			FROM #SegmentAlignmentResults res
			LEFT OUTER JOIN #DistinctCounts cnt
				ON res.TableName = cnt.TableName COLLATE DATABASE_DEFAULT 
					AND res.ColumnName = cnt.ColumnName COLLATE DATABASE_DEFAULT
					AND res.[Partition] = cnt.PartitionId
			LEFT OUTER JOIN #CachedAccessToColumnstore cache
				ON res.TableName = cache.TableName COLLATE DATABASE_DEFAULT 
					AND res.ColumnName = cache.ColumnName COLLATE DATABASE_DEFAULT
			ORDER BY res.TableName, res.Partition, res.[Column Id];

	END
	ELSE
	BEGIN
		SELECT res.*
				FROM #SegmentAlignmentResults res
			ORDER BY res.TableName, res.Partition, res.[Column Id];
	END

	-- Cleanup
	DROP TABLE IF EXISTS #SegmentAlignmentResults;
	DROP TABLE IF EXISTS #DistinctCounts;
	DROP TABLE IF EXISTS #CachedAccessToColumnstore;

end

GO
