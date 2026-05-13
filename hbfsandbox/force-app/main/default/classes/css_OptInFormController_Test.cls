@isTest

public class css_OptInFormController_Test {
    
  static final String testContactFirstName = 'Test FirstName';
  static final String testContactLastName = 'Test LastName';
  static final String testContactEmail = 'test@gmail.com';
    
  public class contactInfo {
    public String contactFirstName;
    public String contactLastName;
    public String contactEmail;  
  }

  @testSetup static void setup() {
    //Create Contact
      Contact testContact = new Contact(
        FirstName = testContactFirstName,
        LastName = testContactLastName,
        Email = testContactEmail
      ); insert testContact;
  } // end setup

    @isTest static void submitNewContact_Test() {
      // Submit New Contact
      contactInfo newContact = new contactInfo();
        newContact.contactFirstName = 'testContactFirstName';
        newContact.contactLastName = 'testContactLastName';
        newContact.contactEmail = 'newContact@gmail.com';

      String newContactId = css_OptInFormController.submitOptinForm(JSON.serialize(newContact));  
        System.debug('newContactId: '+newContactId);

      // Get All Contacts
        List<Contact> allContacts = [SELECT Id, FirstName, LastName, Email FROM Contact];
        System.debug('allContacts: '+allContacts);
        System.AssertEquals(2,allContacts.size());
    } // end submitNewContact_Test

    @isTest static void submitExistingContact_Test() {
      // Submit Existing Contact
      contactInfo newContact = new contactInfo();
        newContact.contactFirstName = testContactFirstName;
        newContact.contactLastName = testContactLastName;
        newContact.contactEmail = testContactEmail;

      String newContactId = css_OptInFormController.submitOptinForm(JSON.serialize(newContact));  
        System.debug('newContactId: '+newContactId);

      // Get All Contacts
        List<Contact> allContacts = [SELECT Id, FirstName, LastName, Email FROM Contact];
        System.debug('allContacts: '+allContacts);
        System.AssertEquals(1,allContacts.size());
    } // end submitExistingContact_Test
    
}