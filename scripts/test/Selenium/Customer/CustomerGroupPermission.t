# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

# get selenium object
my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        # get needed objects
        my $Helper       = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # enable customer group support
        $Helper->ConfigSettingChange(
            Valid => 1,
            Key   => 'CustomerGroupSupport',
            Value => 1,
        );

        # create test user
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups => [ 'admin', 'users' ],
        ) || die "Did not get test user";

        # create test customer
        my $TestCustomerUserLogin = $Helper->TestCustomerUserCreate(
        ) || die "Did not get test customer user";

        # create test tickets
        my @TicketIDs;
        my @TicketNumbers;
        for my $TestTickets ( 1 .. 5 ) {
            my $TicketNumber = $TicketObject->TicketCreateNumber();
            my $TicketID     = $TicketObject->TicketCreate(
                TN           => $TicketNumber,
                Title        => 'Selenium Test Ticket',
                Queue        => 'Raw',
                Lock         => 'unlock',
                Priority     => '3 normal',
                State        => 'open',
                CustomerID   => $TestCustomerUserLogin,
                CustomerUser => $TestCustomerUserLogin,
                OwnerID      => 1,
                UserID       => 1,
            );
            $Self->True(
                $TicketID,
                "Ticket is created - ID $TicketID, TN $TicketNumber ",
            );
            push @TicketIDs,     $TicketID;
            push @TicketNumbers, $TicketNumber;
        }

        # login test user
        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # create test group
        my $GroupName = 'Group' . $Helper->GetRandomID();
        my $GroupID   = $Kernel::OM->Get('Kernel::System::Group')->GroupAdd(
            Name    => $GroupName,
            ValidID => 1,
            UserID  => 1,
        );
        $Self->True(
            $GroupID,
            "Group is created - $GroupName",
        );

        # get script alias
        my $ScriptAlias = $Kernel::OM->Get('Kernel::Config')->Get('ScriptAlias');

        # navigate to sysconfig CustomerFrontend::Module###CustomerTicketOverview screen
        $Selenium->VerifiedGet(
            "${ScriptAlias}index.pl?Action=AdminSysConfig;Subaction=Edit;SysConfigSubGroup=Frontend%3A%3ACustomer%3A%3AModuleRegistration;SysConfigGroup=Ticket"
        );

        # add test group as group restriction for company ticket subaction screen
        $Selenium->find_element(
            "//button[\@name='CustomerFrontend::Module###CustomerTicketOverview#NavBar3#NewGroupElement'][\@type='submit']"
        )->VerifiedClick();

        my $ConfigGroupElement = $Selenium->find_element(
            "//input[\@name='CustomerFrontend::Module###CustomerTicketOverview#NavBar3#Group[]']"
        );
        $ConfigGroupElement->send_keys($GroupName);
        $ConfigGroupElement->VerifiedSubmit();

        # login test customer user
        $Selenium->Login(
            Type     => 'Customer',
            User     => $TestCustomerUserLogin,
            Password => $TestCustomerUserLogin,
        );

        # navigate to CompanyTickets subaction screen
        $Selenium->VerifiedGet("${ScriptAlias}customer.pl?Action=CustomerTicketOverview;Subaction=CompanyTickets");

        # check for customer user fatal error
        my $ExpectedMsg = 'Please contact the administrator.';
        $Self->True(
            index( $Selenium->get_page_source(), $ExpectedMsg ) > -1,
            "Customer fatal error message - found",
        );

        # set customer user in test group with rw and ro permissions
        my $Success = $Kernel::OM->Get('Kernel::System::CustomerGroup')->GroupMemberAdd(
            GID        => $GroupID,
            UID        => $TestCustomerUserLogin,
            Permission => {
                ro => 1,
                rw => 1,
            },
            UserID => 1,
        );
        $Self->True(
            $Success,
            "CustomerUser $TestCustomerUserLogin added to test group $GroupName with ro and rw rights"
        );

        # login test customer user again
        $Selenium->Login(
            Type     => 'Customer',
            User     => $TestCustomerUserLogin,
            Password => $TestCustomerUserLogin,
        );

        # navigate to CompanyTickets subaction screen again
        $Selenium->VerifiedGet("${ScriptAlias}customer.pl?Action=CustomerTicketOverview;Subaction=CompanyTickets");

        # verify there is no more customer fatal message
        $Self->True(
            index( $Selenium->get_page_source(), $ExpectedMsg ) == -1,
            "Customer fatal error message - not found",
        );

        # check for test ticket numbers on search screen
        for my $CheckTicketNumbers (@TicketNumbers) {
            $Self->True(
                index( $Selenium->get_page_source(), $CheckTicketNumbers ) > -1,
                "TicketNumber $CheckTicketNumbers - found on screen"
            );
        }

        # delete test created group
        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');
        $Success = $DBObject->Do(
            SQL => "DELETE FROM group_customer_user WHERE group_id = $GroupID",
        );
        if ($Success) {
            $Self->True(
                $Success,
                "$GroupName - GroupCustomerUserDelete",
            );
        }

        $GroupName = $DBObject->Quote($GroupName);
        $Success   = $DBObject->Do(
            SQL  => "DELETE FROM groups WHERE name = ?",
            Bind => [ \$GroupName ],
        );
        $Self->True(
            $Success,
            "Delete group - $GroupName",
        );

        # delete created test tickets
        for my $TicketID (@TicketIDs) {

            my $Success = $TicketObject->TicketDelete(
                TicketID => $TicketID,
                UserID   => 1,
            );
            $Self->True(
                $Success,
                "Delete ticket - $TicketID"
            );
        }

        # make sure the cache is correct
        for my $Cache (
            qw (Ticket CustomerGroup Group )
            )
        {
            $Kernel::OM->Get('Kernel::System::Cache')->CleanUp(
                Type => $Cache,
            );
        }
    }
);

1;
