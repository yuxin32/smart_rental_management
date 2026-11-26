export function invitationText(name: string, email: string, password: string): string {
  return `Dear ${name},

Welcome to Smart Rental Management.

Your apartment administrator has created a tenant account for you. Please download and install the Smart Rental Management application using the installation file provided by apartment management.

Open the application, select Tenant Login, and sign in using the following details:

Email address: ${email}
Temporary password: ${password}

You will be asked to set a new password on your first sign-in. Once it is saved, sign in again with your new password and follow the instructions to submit your supporting documents.

Keep your password confidential. Do not share this email or your login details with anyone. Apartment management will never ask you to disclose your password.

If you were not expecting this invitation or need the application installation file, please contact your apartment administrator.

Kind regards,
Apartment Management
Smart Rental Management`;
}
