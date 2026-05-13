global with sharing class css_OptInFormController {
  Static final String className = 'css_OptInFormController:';                       

  public class contactInfo {
    public String contactFirstName;
    public String contactLastName;
    public String contactEmail;  
  }

  @RemoteAction
  global static String submitOptinForm(String jsonOptinInfo) {
    String methodName = 'submitOptinForm';                        

    String returnVal = 'no contacts';                           

    contactInfo oInfo = (contactInfo)JSON.deserialize(jsonOptinInfo, contactInfo.class);
      System.debug(className+methodName+' - jsonOptinInfo: ' +jsonOptinInfo);
      System.debug(className+methodName+' - oInfo: ' +oInfo);      

    Contact oContact = null;
      
      List<Contact> oContacts = [SELECT Id, FirstName, LastName, Email, css_frm__NewsletterOptIn__c FROM Contact
                                 WHERE FirstName=:oInfo.contactFirstName AND Email=:oInfo.contactEmail AND IsDeleted = false];

    if(!oContacts.isEmpty()) {
        oContact = oContacts[0];
          System.debug(className+methodName+' - Existing contact: '+oContact);
        oContact.FirstName = oInfo.contactFirstName;
        oContact.LastName = oInfo.contactLastName; 
        oContact.Email = oInfo.contactEmail;
        oContact.css_frm__NewsletterOptIn__c = true;
        upsert oContact;
        returnVal = oContact.Id;
      } else {
        oContact = new Contact(
          FirstName = oInfo.contactFirstName,
          LastName = oInfo.contactLastName,
          Email = oInfo.contactEmail,
          css_frm__NewsletterOptIn__c = true
          );
        insert oContact;
          System.debug(className+methodName+' - New contact: '+oContact);
        returnVal = oContact.Id;
      }                        
    return returnVal;
  } // end submitOptinForm
}