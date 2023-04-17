# ALEPH---Check-of-items
Scripts for checking item location, item status, call number, material and barcode accrodign to extra settings table. Checks can be run extraordinary or as a check durign saving bibliogr. record. 
Created by Matyas Bajger, 2016


The extension allows that **items in ADM base(s) are checked according to settings configured by admin in “ALEPH-like” table in $data_tab directory**. There are _two possibilities_ of this check:

1) as independent script that might be scheduled executed and can send results (mistakes) to email;

2) on-the-fly checks during save of BIB record using own expand/fix procedure and other standard ALEPH fix + check settings. This setting is a bit more complicated, but allows checks straight during modification of records (unfortunately only BIB records)

Both scripts are in Perl using Perl modules available in ALEPH distribution of Perl.

Since there is no check of items in ALEPH as to particular library collection branching and division, some or more items can be easily entered wrongly causing a cathouse in the collection. For a quite simple library collection, a SQL query to z30 may be sufficient for such checks. Yet, if the library structure gets more complicated, such “select” becomes labyrinthine and another tool with simple administration might be handy.

See - download documentation - manual from [http://aleph.osu.cz/item_check/Aleph_item_location_check.pdf](http://aleph.osu.cz/item_check/Aleph_item_location_check.pdf)

Get pack with files from [http://aleph.osu.cz/item_check/item_check_pack.tar.gz](http://aleph.osu.cz/item_check/item_check_pack.tar.gz) 
