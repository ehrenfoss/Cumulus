/*
Copyright (c) 2011, salesforce.com foundation, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, 
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, 
    this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice, 
    this list of conditions and the following disclaimer in the documentation 
    and/or other materials provided with the distribution.
    * Neither the name of the salesforce.com foundation. nor the names of its contributors 
    may be used to endorse or promote products derived from this software 
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
OF THE POSSIBILITY OF SUCH DAMAGE.

*/
/**
* @author Team Kick Ass; Veronica Waters, Evan Callahan, Derek Dsouza, Mike Fullmore
* @date 04/27/2011
* @description controller for the batch entry page.
*/

public with sharing class BDE_BatchEntry_CTRL {

        public batch__c batch { get; set; }
        public boolean displayBatchSection { get; set; }   // could be transient?
        public boolean displayRecInfoSection { get; set; }     // could be transient?
        public boolean displaySettingsSection { get; set; }     // could be transient?
        public boolean startNewBatch {get; set;}             // EF lazy, can't use presence of objname as the trigger anymore though
        
        public List<SelectOption> objectSettingsList { get; private set; }
        
        public BatchItem currentItem { get; set; }   // could be transient - already getting it on edit, otherwise should be clear (what about errors?)
        public list<BatchItem> itemList { get; set; }   // could be transient - would need list of ids instead

        // could get all this every time, but not a lot of viewstate
        public string objname { get; set; }
        
        // EOF set of parent object names included in this batch
        // and sets of entry and list fields per object name
        public list<string> objnames {get; set;}
        public map<string,list<EntryField>> entryFieldLists { get; set; }
        public map<string,list<string>> listFieldLists { get; set; }
        public map<string,list<BatchItem>> itemLists { get; set; }
        
        public string batchLookupField { get; private set; }
        public string pageSubtitle { get; private set; }
        public list<EntryField> entryFieldList { get; private set; }
        public list<string> listFieldList { get; private set; }
        
        public Batch_Data_Entry_Settings__c bdec {get; set;}
        
        public integer itemCount { get { return (itemList != null) ? itemList.size() : 0; } }
                
        public map<id, OpportunityContactRole> ocrlookup;
        
        public BDE_BatchEntry_CTRL(ApexPages.StandardController stdController) {
                
                System.debug('EF controller ');    
                objnames = new List<string>();

                if (stdController.getId() == null) {
                    batch = new Batch__c();
                    batch.Object_Name__c = ApexPages.currentPage().getParameters().get('obj');
                    batch.Included_Objects__c = batch.Object_Name__c;
                }
                
                //query dynamically to retrieve any custom fields from the field set
                else{
                    
                    String q = 'select ';
                    Map<String, Schema.SObjectField> batchObjMap = schema.SObjectType.Batch__c.fields.getMap();
                    List<Schema.SObjectField> batchFldList = batchObjMap.values();
                                                
                    for(Schema.SObjectField s : batchFldList){
                        q += s.getDescribe().getName() + ', ';   
                    }

                    q = q.subString(0, q.length() - 2);
                    UTIL_Debug.debug('Q IS: ' + q);
                    q += ' from ' + UTIL_Namespace.StrTokenNSPrefix('Batch__c') + ' where id = \'' + stdController.getId() + '\' limit 1';
                    batch = Database.query(q);        

                    // EOF initialize set of objnames
                    if (batch.included_objects__c != null) {
                        objnames = batch.included_objects__c.split(',',-1);
                    } else if (batch.object_name__c != null) {
                        objnames.add(batch.object_name__c);
                    }     
                }

                                    
                objname = (batch.id != null) ? 
                        batch.object_name__c :
                        ApexPages.currentPage().getParameters().get('obj'); 
                                             
        }
        
        // EOF abstract to function per object
        // list of field sets per object     
        public void initializeBatchEntryOfObject(String objname){
            BDE_BatchDataEntry bde = new BDE_BatchDataEntry(objname);                
            if (!bde.getStatusMessage().contains(bde.getFailureMessage())){   
                objname = bde.getObjectName();
                // what does this check do?                    
                if(objname!=null) {
                    batchLookupField = bde.getBatchLookupFieldname();
                    
                    String pluralName = BDE_DescribeHelper_UTIL.getObjectDescribe(objname).getLabelPlural();
                    entryFieldList = new list<EntryField>();
                    
                    for (string fn : bde.getEntryFieldList())
                        entryFieldList.add(new EntryField(objname, fn));
                    
                    entryFieldLists.put(objname,entryFieldList);
                    listFieldLists.put(objname,bde.getListFieldList()); 
                                 
                    list<BatchItem> tmpItemList = new list<BatchItem>();
                    
                    if (batch.id != null) {
                        string q = bde.getQueryString();
                        q += ' where ' + batchLookupField + ' = \'' + batch.id + '\'';
                          
                        list<sobject> existingsobjs = database.query(q);
                        for (sObject existing : existingsobjs) {
                           tmpItemList.add(new BatchItem(this, existing));
                        }
                        itemLists.put(objname,tmpItemList);
                        // EF not sure if this is a good idea, but allows for itemCount, etc for now
                        // will there be skew between itemList and itemLists?
                        itemList.addAll(tmpItemList);
                    } else {
                        itemLists.put(objname,new List<BatchItem>());
                    }
                }
            } else{             
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, bde.getStatusMessage()));
                displaySettingsSection = false;
                displayBatchSection = false;
                displayRecInfoSection = false;
            }       
        }
        
        public void initializeBatchEntry(){
               
            System.debug('EF initialize batch entry');    
               
            bdec = UTIL_CustomSettingsFacade.getBDESettings();
            
            entryFieldLists = new Map<String,List<EntryField>>();
            listFieldLists = new Map<String,List<String>>();
            itemLists = new Map<String,List<BatchItem>>();
            itemList = new list<BatchItem>();
            
            //no defaults yet loaded, create one
            if (bdec == null){
                bdec = new Batch_Data_Entry_Settings__c();
                insert bdec;
            }     
            
            // EOF iterate over included objects and initialize
            if (objnames.size() > 0) {
                for(String obj : objnames) {
                    System.debug('EOF initializing object: ' + obj);
                    initializeBatchEntryOfObject(obj);
                }
                System.debug('EOF objnames: ' + objnames);
                System.debug('EOF items: ' + itemLists);
                System.debug('EOF listfields: ' + listFieldLists);
                displayBatchSection = true;
                displayRecInfoSection = true;  
                
                if (currentItem == null) {
                    currentItem = new BatchItem(this,objname);
                }
                                  
            } else {
                    
                System.debug('EOF need object settings, list: ' + objectSettingsList);    
                    
                pageSubtitle = 'Batch Data Entry Home';
                displaySettingsSection = true;
                displayBatchSection = true;
                displayRecInfoSection = false;  
            }
            
            entryFieldList = entryFieldLists.get(objname);
            
            objectSettingsList = new List<SelectOption>();
            map<string, string> mapBDE = BDE_BatchDataEntry.mapDevNameToLabelBDEObjects();
            for(String strDevName : mapBDE.keySet()) {
                objectSettingsList.add(new SelectOption(strDevName, mapBDE.get(strDevName)));
            }
            
        }
        
        private void requeryItem(BatchItem item)  {
        
            BDE_BatchDataEntry bde = new BDE_BatchDataEntry(objname);                          
            string q = bde.getQueryString();
            q += ' where Id=' +  '\'' + item.sobj.id + '\'';
            list<sobject> existingsobjs = database.query(q);
            if (existingsobjs.size() > 0) {
                item.sobj = existingsobjs[0];
            } 
        } 
        
        /********** CLASSES ****************/
        
        public class EntryField {
                public string fieldName { get; private set; }
                public string fieldLabel { get; private set; }
                        
                public entryField(string obj, string fld) {
                    fieldName = fld;
                    fieldLabel = BDE_DescribeHelper_UTIL.getFieldLabel(obj, fld);
                    if(fieldName.toUpperCase().endsWith('ID') && fieldLabel.toUpperCase().endsWith('ID'))     
                        fieldLabel=fieldLabel.substring(0, fieldLabel.length()-2);               
                }
        }
    
        public class BatchItem {
                                
                BDE_BatchEntry_CTRL mydad;
                public integer itemNum { get; private set; }
                public sobject sobj { get; set; }
                public boolean renderNPSPContact{get; set;} 
                public string bi_objname;
                public List<BatchItem> children { get; set;}
                
                //empty object for using the 
                //ocr ContactID lookup field for NPSP donations
                public OpportunityContactRole npspocr {get; set;}
                                
                public BatchItem(BDE_BatchEntry_CTRL parentClass,string objname) {
                        mydad = parentClass;       
                        bi_objname = objname;
                        
                        sobj = BDE_DescribeHelper_UTIL.getPrototypeObject(objname); //this line needs to be outside the check for displayBatchSection or we get an error on page load for any object where !displayBatchSection          
                        renderNPSPContact = false;
                        
                        if (mydad.displayBatchSection) {
                            sobj.put(mydad.batchLookupField, parentClass.batch.id);
                        }
                        
                        //generate a 'dummy' ocr for npsp donation entry
                        if (mydad.objname == 'opportunity'){
                            npspocr = new OpportunityContactRole();
                            renderNPSPContact = true;
                        }   
                                             
                }
                
                public BatchItem(BDE_BatchEntry_CTRL parentClass, sobject existingItem) {
                    mydad = parentClass;
                    sobj = existingItem;
                    bi_objname = sobj.getsObjectType().getDescribe().getName();
                    
                    renderNPSPContact = false;
                    //get the actual primary ocr for this npsp opp
                    if(sobj.getSObjectType() == Opportunity.Sobjecttype && mydad.ocrlookup != null){
                        npspocr = mydad.ocrlookup.get(sobj.id);
                        renderNPSPContact = true;
                    }                                                
                }
                
                public pageReference editItem() {
                    // load this item into data entry section
                    myDad.currentItem = this;
                    myDad.objname = this.bi_objname;
                    myDad.entryFieldList = myDad.entryFieldLists.get(this.bi_objname);
                    System.debug('EOF editItem objname ' + this.bi_objname);
                    System.debug('EOF editItem entryFieldList ' + myDad.entryFieldList);
                    
                    return null;
                }
                
                public pageReference deleteItem() {
                    // delete this item from the list
                    myDad.deleteItem(sobj);
                    return null;
                                    
                }
                
                public pageReference viewItem(){
                    ApexPages.Pagereference pr = new ApexPages.Pagereference('/' + sobj.id);
                    return pr;
                }
                
                //automatic donation naming 
                public string createName(){
                    string namestring = '';
                    
                    //if we have an NPSP Contact, start there, else, use the account name
                    if (npspocr != null && npspocr.ContactID != null){
                        namestring += [select Name from Contact where id = :npspocr.ContactID].Name;
                    }
                    else{
                        id accid = (id)sobj.get('AccountID');
                        if (accid != null){
                           namestring += [select Name from Account where id = :accid].Name;
                        }
                    } 
                     
                    date oppdate = (date)sobj.get('CloseDate');
                    namestring += ' ' + oppdate.format();
                    
                    if (sobj.get('RecordTypeID') != null){
                        id recid = (id)sobj.get('RecordTypeID');
                        namestring += ' ' + [select Name from RecordType where id = :recid].Name;
                    }
                                                            
                    return namestring; 
                }
        }
        
        /***** OTHER CONTROLLER METHODS ******/
        
        public pageReference saveBatch() {          
            Savepoint sp = Database.setSavepoint();         
            try {
                TDTM_Runnable.DmlWrapper dmlWrapper = new TDTM_Runnable.DmlWrapper();
                // if we are using batch, save the batch                
                if (displayBatchSection && itemList!=null) {
                    batch.number_of_items__c = itemList.size();
                    batch.Included_Objects__c = String.join(objnames,',');

                    if (batch.id == null)
                        dmlWrapper.objectsToInsert.add(batch);
                    else
                        dmlWrapper.objectsToUpdate.add(batch);
                }
                TDTM_TriggerHandler.processDML(dmlWrapper);
            
            } catch(Exception e) {
                Database.rollback(sp);
                ERR_Handler.processError(e, batch, ERR_Handler.Context.BDE);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));  
            }
            return null;
        }
        
        public pageReference save() {
            Savepoint sp = Database.setSavepoint();
            
            try {
                if (currentItem.sobj.id != null) {
                    if(currentItem.sobj.getSObjectType() == Opportunity.Sobjecttype){
                            currentItem.sobj.put('npe01__Contact_ID_for_Role__c', currentItem.npspocr.ContactID);
                    }
                    
                    //update the name in case values have changed
                    if(currentItem.sobj.getSObjectType() == Opportunity.Sobjecttype && (bdec.Opportunity_Naming__c == true || (bdec.Allow_Blank_Opportunity_Names__c == false && currentItem.sobj.get('Name') == null))){                       
                            currentItem.sobj.put('Name', currentItem.createName());
                    }
                    
                    update currentItem.sobj;
                } else {         
                        if(currentItem.sobj.getSObjectType() == Opportunity.Sobjecttype){
                            currentItem.sobj.put('npe01__Contact_ID_for_Role__c', currentItem.npspocr.ContactID);
                        }
                      
                        //use automatic opp naming 
                        if(currentItem.sobj.getSObjectType() == Opportunity.Sobjecttype && (bdec.Opportunity_Naming__c == true || (bdec.Allow_Blank_Opportunity_Names__c == false && currentItem.sobj.get('Name') == null))){
                            currentItem.sobj.put('Name', currentItem.createName());
                        }
                        
                        if (itemList.isEmpty()) {
                                itemList.add(currentItem);
                                saveBatch();
                                //we can't guarantee a lookup field when running tests
                                //so skip this line when in a test context
                                //if (!test.isRunningTest())  DJH: OK to assume Opportunity has batch__c
                                    currentItem.sobj.put(batchLookupField, batch.Id);
                                
                                insert currentItem.sobj;                                
                        }
                        else {
                                insert currentItem.sobj; 
                                itemList.add(0, currentItem);
                        }                        
                }
                saveBatch();
                
                // update the current item, in case any triggers modified values we will display.
                requeryItem(currentItem);
                // ef fixme later
                currentItem = new BatchItem(this,currentItem.sobj.getSObjectType().getDescribe().getName());
                return null; 
            } catch(Exception e) {
                Database.rollback(sp);
                ERR_Handler.processError(e, batch, ERR_Handler.Context.BDE);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
            }
            return null;   
        }

        public pageReference clear() {
                // ef this might break?
                currentItem = null;
                return null;
        }
        
        public void deleteItem(sobject sobj) {
            Savepoint sp = Database.setSavepoint();
            try {
                delete sobj;
                for (integer i = 0; i < itemList.size(); i++) {
                        if (itemList[i].sobj.id == sobj.id) { 
                                itemList.remove(i);
                                break;
                        }
                }
                saveBatch();
            } catch(Exception e) {
                Database.rollback(sp);
                ERR_Handler.processError(e, ERR_Handler.Context.BDE);
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, e.getMessage()));
            }        
        }
        
        public pageReference openBatchEnterPage() {
            PageReference pageRef = Page.BDE_BatchEntry;
            startNewBatch = true;
            pageRef.getParameters().put('obj', objName);
            pageRef.setRedirect(true);
            return pageRef;         
        }      
        
        public pageReference addNewObject() {
            PageReference pageRef = Page.BDE_BatchEntry;
            currentItem = new BatchItem(this,objName);
            boolean objExists = false;
            for(String obj : objnames) {
                if (obj == objName) { objExists = true; }
            }            
            if (!objExists) 
                objnames.add(objName);
                
            initializeBatchEntry();
            entryFieldList = entryFieldLists.get(objName);
            System.debug('EOF entry field list add new object ' + entryFieldList);
            //pageRef.setRedirect(true);
            return pageRef;
        }             
       
}