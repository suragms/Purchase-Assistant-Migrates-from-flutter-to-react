"use client";

import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { LuSettings2 } from "react-icons/lu";

const SettingsPage = () => {
  return (
    <div className="p-4">
      <Card>
        <CardHeader className="flex flex-row items-center gap-4">
          <div className="bg-gray-100 p-2 rounded-lg">
            <LuSettings2 className="h-6 w-6 text-gray-600" />
          </div>
          <div>
            <CardTitle>Settings</CardTitle>
            <CardDescription>Manage your account and app settings</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <div className="p-4 border rounded-lg">
              <p className="text-sm text-gray-500">Settings options will appear here</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default SettingsPage;